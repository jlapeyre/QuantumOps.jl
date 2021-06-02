function Base.:*(t1::OpTerm{T, V}, t2::OpTerm{T, V}) where {T<:AbstractOp, V<:SparseArraysN.SparseVector{T}}
    (t_out, phase) = mul(t1.ops, t2.ops)
    return OpTerm(t_out, phase * t1.coeff * t2.coeff)
end

function mul(v1::SparseArraysN.SparseVector{T}, v2::SparseArraysN.SparseVector{T}) where {T <: AbstractOp}
    vals = T[]
    inds = empty(v1.nzind)
    phase_data = (0, 0)
    i1 = 1  # index into terms in t1
    i2 = 1
    while i1 <= weight(v1) && i2 <= weight(v2)
        ind1 = v1.nzind[i1]
        ind2 = v2.nzind[i2]
        val1 = v1.nzval[i1]
        val2 = v2.nzval[i2]
        ## ind1 corresponds to non-structural identity in v2
        ## Multiplying v1[ind1] by identity gives v1[ind1], so we just push
        ## this value to the result.
        if ind1 < ind2
            push!(inds, ind1)
            push!(vals, val1)
            i1 += 1
        ## Symmetric to the case above.
        elseif ind1 > ind2
            push!(inds, ind2)
            push!(vals, val2)
            i2 += 1
        else  # tt1.op and tt2.op operate on the same index (DOF)
            ## Only here do we multiply non-trivial factors
            new_op = val1 * val2
            if iszero(new_op)  # if any factor vanishes, the term vanishes.
                return (SparseArraysN.SparseVector(0, empty!(inds), empty!(vals)), 0)
            end
            i1 += 1
            i2 += 1
            if isone(new_op)  # Identity is not stored in sparse representation
                continue
            end
            phase_data = accumulate_phase(phase_data, val1, val2)
            push!(inds, ind1)
            push!(vals, new_op)
        end
    end
    ## Include remaining factors from the longer string
    if i1 <= weight(v1)
        for i in i1:weight(v1)
            push!(inds, v1.nzind[i])
            push!(vals, v1.nzval[i])
        end
    elseif i2 <= weight(v2)
        for i in i2:weight(v2)
            push!(inds, v2.nzind[i])
            push!(vals, v2.nzval[i])
        end
    end
    return (SparseArraysN.SparseVector(inds[end], inds, vals), compute_phase(T, phase_data))
end

function Base.show(io::IO, term::OpTerm{T, <:SparseArraysN.SparseVector}) where {T}
    ops = term.ops
    xnnz = length(ops.nzind)
    print(io, length(term), "-element ", typeof(term), " with ", xnnz,
          " stored ", xnnz == 1 ? "entry" : "entries")
    if xnnz != 0
        print(io, ":\n")
        for i in 1:length(ops.nzind)
            print(io, ops.nzval[i], ops.nzind[i])
            if i < length(ops.nzind)
                print(io, " ")
            end
        end
        print(io, " * ")
        if term.coeff isa Real
            print(io, term.coeff)
        else
            print(io, "(", term.coeff, ")")
        end
    end
end
