abstract type AbstractTerm{W} end

## type params only to get correct dispatch. There must be a better way
function Base.show(io::IO, term::AbstractTerm) # where { T, V, CoeffT, AbstractTerm{T,V,CoeffT}}
    print(io, op_string(term))
    print(io, " * ")
    if term.coeff isa Real  # could use CoeffT here.
        print(io, term.coeff)
    else
        print(io, "(", term.coeff, ")")
    end
end

Base.one(term::AbstractTerm{W}) where {W} = typeof(term)(fill(one(W), length(term)), one(term.coeff))

Base.:(==)(op1::AbstractTerm, op2::AbstractTerm) = op1.coeff == op2.coeff && op_string(op1) == op_string(op2)

_isless(x, y) = isless(x, y)
_isless(x::Complex, y::Complex) = isless(abs2(x), abs2(y))

function Base.isless(op1::AbstractTerm, op2::AbstractTerm)
    if op_string(op1) == op_string(op2)
        return _isless(op1.coeff, op2.coeff)
    end
    return isless(op_string(op1), op_string(op2))
end

####
#### Container interface
####

# :popat!
for func in (:length, :size, :eltype, :eachindex, :axes, :splice!, :getindex,
             :setindex!, :iterate, :pop!, :popfirst!)
    @eval begin
        Base.$func(ps::AbstractTerm, args...) = $func(op_string(ps), args...)
    end
end

for func in (:push!, :pushfirst!, :insert!)
    @eval begin
        Base.$func(ps::AbstractTerm, args...) = ($func(op_string(ps), args...); ps)
    end
end

####
#### Algebra
####

Base.:*(z::Number, term::AbstractTerm) = typeof(term)(op_string(term), term.coeff * z)
Base.:*(ps::AbstractTerm, z::Number) = z * ps