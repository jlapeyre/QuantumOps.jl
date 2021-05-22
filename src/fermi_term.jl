using .FermiOps: number_op, raise_op, lower_op, no_op, id_op

#struct FermiTerm{T} <: AbstractTerm
struct FermiTerm{W<:AbstractFermiOp, T<:AbstractVector{W}, V} <: AbstractTerm{W}
    ops::T
    coeff::V
end

op_string(t::FermiTerm) = t.ops

term_type(::Type{<:AbstractFermiOp}) = FermiTerm

####
#### Constructors
####

function FermiTerm(::Type{T}, s::AbstractString, coeff=_DEFAULT_COEFF) where T <: AbstractFermiOp
    return FermiTerm(Vector{T}(s), coeff)
end

FermiTerm(s::AbstractString, coeff=_DEFAULT_COEFF) = FermiTerm(FermiOp, s, coeff)

function FermiTerm(inds::NTuple{N, Int}, coeff, n_modes::Integer) where N
    (ops, phase) = index_to_ops_phase(inds)
    (factors, new_coeff) = _fermi_term(ops, phase, coeff, n_modes)
    return FermiTerm(factors, new_coeff)
end

index_to_ops(inds) = index_to_ops(inds...)

function index_to_ops(i, j, k, l)
    if i == j || k == l
        return ()  # unstable, use a barrier or move this out
    end
    if i == k || i == l
        op1 = (op=number_op, ind=i)
    else
        op1 = (op=raise_op, ind=i)
    end
    if j == k || j == l
        op2 = (op=number_op, ind=j)
    else
        op2 = (op=raise_op, ind=j)
    end
    if k != i && k != j
        op3 = (op=lower_op, ind=k)
    else
        op3 = (op=no_op, ind=k)
    end
    if l != i && l != j
        op4 = (op=lower_op, ind=l)
    else
        op4 = (op=no_op, ind=k)
    end
    return (op1, op2, op3, op4)
end

function index_to_ops(i, j)
    if i == j
        return ((op=number_op, ind=i), )
    end
    if i < j
        return ((op=raise_op, ind=i), (op=lower_op, ind=j))
    else
        return ((op=lower_op, ind=i), (op=raise_op, ind=j))
    end
end

function count_permutations(inds::NTuple{2})
    if inds[2] < inds[1]
        return 1
    else
        return 0
    end
end

index_phase(inds::NTuple) = iseven(count_permutations(inds)) ? 1 : -1

function count_permutations(inds::NTuple{4})
    count = 0
    @inbounds i = inds[1]
    @inbounds for j in (2,3,4)
        if i > inds[j]
            count += 1
        end
    end
    @inbounds i = inds[2]
    @inbounds for j in (3,4)
        if i > inds[j]
            count += 1
        end
    end
    @inbounds i = inds[3]
    @inbounds if i > inds[4]
        count += 1
    end
    return count
end

index_to_ops_phase(inds) = (ops=index_to_ops(inds), phase=index_phase(inds))

## Embed `ops` in a string of width `n_modes`
function _fermi_term(ops::NTuple, phase::Integer, coeff, n_modes::Integer)
    factors = fill(id_op, n_modes)
    for (op, ind) in ops
        if op == no_op
            continue
        end
        factors[ind] = op
    end
    return (factors, phase * coeff)
end

"""
    ferm_terms(two_body)

Convert rank-4 tensor `two_body` to a `Vector` of `FermiTerm`s.
"""
function ferm_terms(two_body)
    n_modes = first(size(two_body))
    terms = FermiTerm{FermiOp, Vector{FermiOp}, eltype(two_body)}[]
    for ind in CartesianIndices(two_body)
        if (ind[1] == ind[2] || ind[3] == ind[4]) || two_body[ind] == 0
            continue
        end
        push!(terms, FermiTerm(ind.I, two_body[ind], n_modes))
    end
    return terms
end

"""
    rand_fermi_term(::Type{FermiT}=FermiDefault, n::Integer; coeff=_DEFAULT_COEFF) where {FermiT <: AbstractFermiOp}

Return a random `FermiTerm` of `n` tensor factors.
"""
function rand_fermi_term(::Type{FermiT}, n::Integer; coeff=_DEFAULT_COEFF) where {FermiT <: AbstractFermiOp}
    return FermiTerm(rand(FermiT, n), coeff)
end

rand_fermi_term(n::Integer; coeff=_DEFAULT_COEFF) = rand_fermi_term(FermiDefault, n, coeff=coeff)

####
#### Compare / predicates
####

function Base.zero(ft::FermiTerm)
    new_string = similar(op_string(ft))
    fill!(new_string, zero_op)
    return FermiTerm(new_string, zero(ft.coeff))
end

Base.iszero(ft::FermiTerm) = iszero(ft.coeff) || any(iszero, op_string(ft))

####
#### Algebra / mathematical operations
####

function Base.:*(ft1::FermiTerm, ft2::FermiTerm)
    if length(ft1) != length(ft2)
        throw(DimensionMismatch())
    end
    new_string = similar(op_string(ft1))
    @inbounds for i in eachindex(ft1)
        _prod = op_string(ft1)[i] * op_string(ft2)[i]
        if iszero(_prod)  # If any factor is zero, the entire product is zero
            fill!(new_string, zero_op)
            return FermiTerm(new_string, zero(ft1.coeff))
        end
        new_string[i] = _prod
    end
    return FermiTerm(new_string, ft1.coeff * ft2.coeff)
end

function Base.:^(ft::FermiTerm, n::Integer)
    n < 0 && throw(DomainError(n))
    n == 0 && return one(ft)
    n == 1 && return ft
    ## Any +,-,0 sends the entire string to zero
    if any(x -> x === raise_op || x === lower_op || x === zero_op, op_string(ft))
        return zero(ft)
    end
    ## E, N, I, are idempotent
    return FermiTerm(copy(op_string(ft)), ft.coeff^n)
end

function Base.adjoint(ft::FermiTerm)
    return FermiTerm(adjoint.(op_string(ft)), conj(ft.coeff))
end
