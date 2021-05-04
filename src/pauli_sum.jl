export PauliSum, add!, lmul!

"""
    struct PauliSum{StringT, CoeffT}

Represents a weighted sum of multi-qubit Pauli strings.
"""
struct PauliSum{StringT, CoeffT}
    strings::StringT
    coeffs::CoeffT

    function PauliSum(strings, coeffs)
        if length(strings) != length(coeffs)
            throw(DimensionMismatch("bad dims"))
        end
        if ! isempty(strings)
            n = length(first(strings))
            if ! all(x -> length(x) == n, strings)
                throw(DimensionMismatch("Pauli strings are of differing lengths."))
            end
            sort_and_sum_duplicates!(strings, coeffs)
        end
        return new{typeof(strings), typeof(coeffs)}(strings, coeffs)
    end
end

"""
    PauliSum(strings)

Construct a sum from `strings` with coefficients all equal to one.
"""
PauliSum(strings) = PauliSum(strings, fill(_default_coeff, length(strings)))

"""
    PauliSum(v::AbstractVector{<:PauliTerm})

Construct a sum from an array of `PauliTerm`s.
"""
function PauliSum(v::AbstractVector{<:PauliTerm})
    strings = [x.paulis for x in v]
    coeffs = [x.coeff for x in v]
    return PauliSum(strings, coeffs)
end

"""
    PauliSum(v::AbstractMatrix{<:AbstractPauli}, coeffs=fill(_default_coeff, size(v, 1)))

Construct a sum from a matrix of single-qubit Pauli operators.
"""
function PauliSum(v::AbstractMatrix{<:AbstractPauli}, coeffs=fill(_default_coeff, size(v, 1)))
    strings = [v[i,:] for i in 1:size(v,1)]
    return PauliSum(strings, coeffs)
end

function sort_and_sum_duplicates!(psum::PauliSum)
    sort_and_sum_duplicates!(psum.strings, psum.coeffs)
    return psum
end

function sort_and_sum_duplicates!(terms, coeffs)
    sort_pauli_sum!(terms, coeffs)
    sum_duplicates!(terms, coeffs)
    remove_zeros!(terms, coeffs)
    return nothing
end

function remove_zeros!(psum::PauliSum)
    remove_zeros!(psum.strings, psum.coeffs)
    return psum
end

"""
    isapprox_zero(x::Number)

Define methods for this function for symbolic
libraries, for example.
"""
function isapprox_zero(x::Number)
    return isapprox(x, zero(x))
end

function remove_zeros!(terms, coeffs)
    inds = findall(x -> isapprox_zero(x), coeffs)
    deleteat!(coeffs, inds)
    deleteat!(terms, inds)
    return nothing
end

# This is 10x faster than the sorting step, even though we
# don't check if all strings are already unique
sum_duplicates!(psum::PauliSum) = sum_duplicates!(psum.strings, psum.coeffs)

# Modeled on code in unique!
"""
    sum_duplicates!(paulis, coeffs)

Find groups of terms whose members differ only in the coefficient.
Replace each group by one term carrying the sum of the coefficients
in that group.
"""
function sum_duplicates!(paulis, coeffs)
    last_pauli::eltype(paulis) = first(paulis)
    coeff = first(coeffs)
    k = 2
    for j in 2:length(paulis)
        if paulis[j] != last_pauli
            last_pauli = paulis[k] = paulis[j]
            coeffs[k] = coeffs[j]
            k += 1
        else
            coeffs[k-1] += coeffs[j]
        end
    end
    resize!(paulis, k-1)
    resize!(coeffs, k-1)
    return nothing
end

# This is expensive. Most time is spent in sortperm
sort_pauli_sum!(psum::PauliSum) = sort_pauli_sum!(psum.strings, psum.coeffs)
function sort_pauli_sum!(strings, coeffs)
    p = sortperm(strings) # alg=MergeSort is 50% faster for 1000x10 strings
    permute!(strings, p)
    permute!(coeffs, p)
    return nothing
end

for func in (:length, :eachindex, :lastindex, :firstindex)
    @eval begin
        function Base.$func(ps::PauliSum, args...)
            return $func(ps.coeffs, args...)
        end
    end
end

# Fails for empty psum
function Base.size(psum::PauliSum)
    return (length(psum), length(first(psum)))
end

function Base.size(psum::PauliSum, i::Integer)
    return size(psum)[i]
end

Base.getindex(psum::PauliSum, j::Integer) = PauliTerm(psum.strings[j], psum.coeffs[j])
Base.getindex(psum::PauliSum, j::Integer, k::Integer) = psum.strings[j][k]
Base.getindex(psum::PauliSum, inds) = PauliSum(psum.strings[inds], psum.coeffs[inds])

# TODO: Should we check that the length of the PauliTerm is correct ?
"""
    push!(psum::PauliSum, ps::PauliTerm...)

Push `ps` to the end of `psum` without regard to order
or possible duplication.

See `sort_and_sum_duplicates!`.
"""
function Base.push!(psum::PauliSum, ps::PauliTerm...)
    for p in ps
        push!(psum.strings, p.paulis)
        push!(psum.coeffs, p.coeff)
    end
    return ps
end

"""
    add!(psum::PauliSum, ps::PauliTerm...)

Add `PauliTerm`s to `psum` in place, assuming `psum` is sorted and
has no repeated strings. Either a new term is inserted, or
the coefficient is added to an existing term. After adding
the `ps`, `psum` will be left sorted and with no duplicates.
"""
function add!(psum::PauliSum, ps::PauliTerm...)
    for p in ps
        inds = searchsorted(psum.strings, p.paulis)
        if length(inds) == 0 # p.paulis not found
            insert!(psum.strings, first(inds), p.paulis)
            insert!(psum.coeffs, first(inds), p.coeff)
        elseif length(inds) == 1 # one element equal to p.paulis
            i = first(inds) # get the (single) index
            psum.coeffs[i] += p.coeff # add p to existing term
            if isapprox_zero(psum.coeffs[i])
                deleteat!(psum.coeffs, [i])
                deleteat!(psum.strings, [i])
            end
        else
            throw(ErrorException("Duplicate terms found in `PauliSum`."))
        end
    end
    return psum
end

"""
    add!(to::PauliSum, from::PauliSum)

Add the terms in `from` to `to` in place.
`to` is mutated. `from` is not.
"""
function add!(to::PauliSum, from::PauliSum)
    for p in from
        add!(to, p)
    end
    return to
end

# We use lmul! because that's how LinearAlgebra offers "scaling" of a Matrix (or rmul!)
"""
    lmul!(psum::PauliSum, n)

Left multiply the coefficient of `psum` by `n` in place.
"""
function LinearAlgebra.lmul!(psum::PauliSum, n)
    psum.coeffs .= n .* psum.coeffs
    return psum
end

# This will fail for an empty `psum`. Use type info instead.
Base.one(psum::PauliSum) = one(first(psum))

Base.:+(terms::T...) where {T <: PauliTerm} = PauliSum([terms...])

Base.:-(psum::PauliSum) = PauliSum(psum.strings, -one(eltype(psum.coeffs)) .* psum.coeffs)

function Base.:(==)(psum1::PauliSum, psum2::PauliSum)
    if length(psum1) != length(psum2)
        return false
    end
    return all(i -> psum1[i] == psum2[i], eachindex(psum1))
end

function Base.show(io::IO, psum::PauliSum)
    for i in eachindex(psum)
        show(io, psum[i])
        if i != lastindex(psum)
            print(io, "\n")
        end
    end
end

# Iterate uses getindex to return `PauliTerm`s.
function Base.iterate(psum::PauliSum, state=1)
    if state > lastindex(psum)
        return nothing
    end
    return (psum[state], state + 1)
end

# Enables using `findall`, for instance.
# Fallback methods for `values` and `pairs` are OK.
function Base.keys(psum::PauliSum)
    return eachindex(psum)
end

Base.Matrix(ps::PauliSum) = sum(Matrix(p) for p in ps)
