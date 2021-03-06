export AbstractTurnBuffer, buffers, RTSA, isfull, consecutive_view

"""
    AbstractTurnBuffer{names, types} <: AbstractArray{NamedTuple{names, types}, 1}

`AbstractTurnBuffer` is supertype of a collection of buffers to store the interactions
between agents and environments. It is a subtype of `AbstractArray{NamedTuple{names, types}, 1}` where `names` specifies which fields are to store and `types` is the coresponding types of the `names`.


| Required Methods| Brief Description |
|:----------------|:------------------|
| `Base.push!(b::AbstractTurnBuffer{names, types}, s[, a, r, d, s′, a′])` | Push a turn info into the buffer. According to different `names` and `types` of the buffer `b`, it may accept different number of arguments |
| `isfull(b)` | Check whether the buffer is full or not |
| `Base.length(b)` | Return the length of buffer |
| `Base.getindex(b::AbstractTurnBuffer{names, types})` | Return a turn of type `NamedTuple{names, types}` |
| `Base.empty!(b)` | Reset the buffer |
| **Optional Methods** | |
| `Base.size(b)` | Return `(length(b),)` by default |
| `Base.isempty(b)` | Check whether the buffer is empty or not. Return `length(b) == 0` by default |
| `Base.lastindex(b)` | Return `length(b)` by default |
"""
abstract type AbstractTurnBuffer{names,types} <: AbstractArray{NamedTuple{names,types},1} end

buffers(b::AbstractTurnBuffer) = getfield(b, :buffers)

Base.size(b::AbstractTurnBuffer) = (length(b),)
Base.lastindex(b::AbstractTurnBuffer) = length(b)
Base.isempty(b::AbstractTurnBuffer) = all(isempty(x) for x in buffers(b))
Base.empty!(b::AbstractTurnBuffer) =
    for x in buffers(b)
        empty!(x)
    end
Base.getindex(b::AbstractTurnBuffer{names,types}, i::Int) where {names,types} =
    NamedTuple{names,types}(Tuple(x[i] for x in buffers(b)))
isfull(b::AbstractTurnBuffer) = all(isfull(x) for x in buffers(b))

function Base.push!(b::AbstractTurnBuffer; kw...)
    for (k, v) in kw
        hasproperty(buffers(b), k) && push!(getproperty(buffers(b), k), v)
    end
end

function Base.push!(b::AbstractTurnBuffer, experience::Pair{<:Observation})
    obs, a = experience
    push!(
        b;
        state = get_state(obs),
        reward = get_reward(obs),
        terminal = get_terminal(obs),
        action = a,
        obs.meta...,
    )
end

#####
# RTSA (Reward, Terminals, State, Action)
#####

state(b::AbstractTurnBuffer) = buffers(b).state
action(b::AbstractTurnBuffer) = buffers(b).action
reward(b::AbstractTurnBuffer) = buffers(b).reward
terminal(b::AbstractTurnBuffer) = buffers(b).terminal

const RTSA = (:reward, :terminal, :state, :action)

Base.getindex(b::AbstractTurnBuffer{RTSA,types}, i::Int) where {types} =
    (
     state = select_frame(state(b), i),
     action = select_frame(action(b), i),
     reward = select_frame(reward(b), i+1),
     terminal = select_frame(terminal(b), i+1),
     next_state = select_frame(state(b), i+1),
     next_action = select_frame(action(b), i+1),
    )

#####
# PRTSA (Prioritized, Reward, Terminal, State, Action)
#####

const PRTSA = (:priority, :reward, :terminal, :state, :action)

priority(b::AbstractTurnBuffer) = buffers(b).priority

Base.getindex(b::AbstractTurnBuffer{PRTSA,types}, i::Int) where {types} =
    (
     state = select_frame(state(b), i),
     action = select_frame(action(b), i),
     reward = select_frame(reward(b), i+1),
     terminal = select_frame(terminal(b), i+1),
     next_state = select_frame(state(b), i+1),
     next_action = select_frame(action(b), i+1),
     priority = select_frame(priority(b), i+1),
    )

function extract_SARTS(buffer, inds, γ, update_horizon, stack_size)
    n = length(inds)
    end_inds = inds .+ update_horizon
    shift_inds = inds .+ 1
    states = consecutive_view(state(buffer), inds, nothing, stack_size)
    actions = consecutive_view(action(buffer), inds, nothing, nothing)
    next_states = consecutive_view(state(buffer), end_inds, nothing, stack_size)
    batch_rewards = consecutive_view(reward(buffer), shift_inds, update_horizon, nothing)
    batch_terminals = consecutive_view(terminal(buffer), shift_inds, update_horizon, nothing)

    rewards, terminals = zeros(Float32, n), fill(false, n)

    # make sure that we only consider experiences in current episode
    for i = 1:n
        t = findfirst(view(batch_terminals, :, i))

        if isnothing(t)
            terminals[i] = false
            rewards[i] = discount_rewards_reduced(view(batch_rewards, :, i), γ)
        else
            terminals[i] = true
            rewards[i] = discount_rewards_reduced(view(batch_rewards, 1:t, i), γ)
        end
    end

    (
        states=states,
        actions=actions,
        rewards=rewards,
        terminals=terminals,
        next_states=next_states
    )
end

Base.length(b::AbstractTurnBuffer) = max(0, length(terminal(b)) - 1)