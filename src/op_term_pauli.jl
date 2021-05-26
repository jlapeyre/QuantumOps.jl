const PauliTerm = OpTerm{Pauli}
const PauliSum = OpSum{Pauli}

"""
    PauliSumA(::Type{PauliT}, matrix::AbstractMatrix{<:Number}; threads=true)

Construct a Pauli decomposition of `matrix`, that is, a `PauliSumA` representing `matrix`.
If `thread` is `true`, use a multi-threaded algorithm for increased performance.
"""
function OpSum{PauliT}(matrix::AbstractMatrix{<:Number}; threads=true) where PauliT <: AbstractPauli
    if threads
        return pauli_sum_from_matrix_threaded(PauliT, matrix)
    else
        return pauli_sum_from_matrix_one_thread(PauliT, matrix)
    end
end

function pauli_sum_from_matrix_one_thread(::Type{PauliT}, matrix::AbstractMatrix{<:Number}) where PauliT
    nside = LinearAlgebra.checksquare(matrix)
    n_qubits = ILog2.checkispow2(nside)
    denom = 2^n_qubits  # == nside
    s = OpSum{PauliT}()
    for pauli in pauli_basis(PauliT, n_qubits)
        mp = SparseArrays.sparse(pauli)  # Much faster than dense
        coeff = LinearAlgebra.dot(mp, matrix)
        if ! isapprox_zero(coeff)
            push!(s, (op_string(pauli), coeff / denom))  # a bit faster than PauliTermA for small `matrix` (eg 2x2)
        end
    end
    return s
end

function pauli_sum_from_matrix_threaded(::Type{PauliT}, matrix::AbstractMatrix{<:Number}) where PauliT
    nside = LinearAlgebra.checksquare(matrix)
    n_qubits = ILog2.checkispow2(nside)
    denom = 2^n_qubits  # == nside
    ## Create a PauliSumA for each thread, for accumulation.
    sums = [OpSum{PauliT}() for i in 1:Threads.nthreads()]
    Threads.@threads for j in 0:(4^n_qubits - 1)
        pauli = OpTerm{PauliT}(j, n_qubits)
        mp = SparseArrays.sparse(pauli)  # Much faster than dense
        coeff = LinearAlgebra.dot(mp, matrix)
        if ! isapprox_zero(coeff)
            push!(sums[Threads.threadid()], (op_string(pauli), coeff / denom))
        end
    end
    for ind in 2:length(sums)  # Collate results from all threads.
        add!(sums[1], sums[ind])
    end
    return sums[1]
end

function OpTerm{T}(index::Integer, n_paulis::Integer, coeff=_DEFAULT_COEFF) where T <: AbstractPauli
    return OpTerm(pauli_vector(T, index, n_paulis), coeff)
end