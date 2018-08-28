"A type for the ensemble average scattering coefficients.
Here they are discretised in terms of the depth x of the halfspace"
type AverageWave{T<:AbstractFloat}
    hankel_order::Int # largest hankel order
    x::Vector{T} # spatial mesh
    amplitudes::Array{Complex{T}} # a matrix of the scattering amplitudes, size(A_mat) = (length(x), 2hankel_order +1)
    # Enforce that the dimensions are correct
    function AverageWave{T}(hankel_order::Int, x::Vector{T}, amplitudes::Array{Complex{T}}) where T <: AbstractFloat
        if (length(x), 2*hankel_order+1) != size(amplitudes)[1:2]
            error("The amplitudes of AverageWave does not satisfy size(amplitudes)[1:2] == (length(X), 2*hankel_order+1)")
        end
        new(hankel_order,x,amplitudes)
    end
end

AverageWave(M::Int, x::AbstractVector{T}, as::AbstractArray{Complex{T}}) where T<:AbstractFloat = AverageWave{T}(M,collect(x),collect(as))

function AverageWave(x::AbstractVector{T}, A_mat::Array{Complex{T}}) where T<:Number
    AverageWave(Int((size(A_mat,2)-1)/2), collect(x), A_mat)
end


"Calculates an AverageWave from one EffectiveWave"
function AverageWave(wave_eff::EffectiveWave{T}, xs::AbstractVector{T}) where T<:Number

    amps = wave_eff.amplitudes
    ho = wave_eff.hankel_order
    θ_eff = wave_eff.θ_eff

    S = size(amps,2)

    average_amps = [
        im^T(m)*exp(-im*m*θ_eff)*amps[m+ho+1,s]*exp(im*wave_eff.k_eff*cos(θ_eff)*x)
    for x in xs, m=-ho:ho, s=1:S]

    return AverageWave(ho,xs,average_amps)
end

"Numerically solved the integral equation governing the average wave. Optionally can use wave_eff to approximate the wave away from the boundary."
function AverageWave(ω::T, medium::Medium{T}, specie::Specie{T};
        radius_multiplier::T = 1.005,
        x::AbstractVector{T} = [zero(T)],
        tol::T = T(1e-4),
        wave_effs::Vector{EffectiveWave{T}} = [zero(EffectiveWave{T})],
    kws...) where T<:Number

    k = real(ω/medium.c)

    if x == [zero(T)]
        if maximum(abs(w.k_eff) for w in wave_effs) == zero(T)
            wave_effs = effective_waves(real(ω/medium.c), medium, [specie];
                radius_multiplier=radius_multiplier, tol=tol, mesh_points=2, kws...)
        end
        # estimate a large coarse non-dimensional mesh based on the lowest attenuating effective wave
        a12 = T(2)*radius_multiplier*specie.r
        x = x_mesh(wave_effs[1]; tol = tol,  a12 = a12)
    end
    
    X = x.*k
    (MM_quad,b_mat) = average_wave_system(ω, X, medium, specie; tol = tol, kws...);

    M = Int( (size(b_mat,2) - 1)/2 )
    J = length(collect(X)) - 1

    len = (J + 1) * (2M + 1)
    MM_mat = reshape(MM_quad, (len, len));
    b = reshape(b_mat, (len));

    As = MM_mat\b
    As_mat = reshape(As, (J+1, 2M+1, 1))

    return AverageWave(M, collect(X)./k, As_mat)
end

"note that this uses the non-dimensional X = k*depth"
function average_wave_system(ω::T, X::AbstractVector{T}, medium::Medium{T}, specie::Specie{T};
        θin::Float64 = 0.0, tol::T = 1e-6,
        radius_multiplier::T = 1.005,
        scheme::Symbol = :trapezoidal,
        hankel_order::Int = maximum_hankel_order(ω, medium, [specie]; tol = tol)
    ) where T<:AbstractFloat

    k = real(ω/medium.c)
    a12k = radius_multiplier*T(2)*real(k*specie.r);
    M = hankel_order;

    J = length(collect(X))
    h = X[2] - X[1]

    Z = OffsetArray{Complex{Float64}}(-M:M);
    for m = 0:M
        Z[m] = Zn(ω,specie,medium,m)
        Z[-m] = Z[m]
    end

    σ = integration_scheme(X; scheme = scheme) # integration scheme: trapezoidal
    PQ_quad = intergrand_kernel(X, a12k; θin = θin, M = M);

    MM_quad = [
        specie.num_density*Z[n]*σ[j]*PQ_quad[l,m+M+1,j,n+M+1] + k^2*( (m==n && j==l) ? 1.0+0.0im : 0.0+0.0im)
    for  l=1:J, m=-M:M, j=1:J, n=-M:M];

    b_mat = [ -k^2*exp(im*X[l]*cos(θin))*exp(im*m*(pi/2.0 - θin)) for l = 1:J, m = -M:M]

    return (MM_quad,b_mat)
end

"Returns x the mesh used to discretise the integral equations."
function x_mesh(wave_eff_long::EffectiveWave{T}, wave_eff_short::EffectiveWave{T} = wave_eff_long;
        tol::T = T(1e-5),  a12::T = zero(T)) where T<:AbstractFloat

    max_x = (-log(tol))/abs(cos(wave_eff_long.θ_eff)*imag(wave_eff_long.k_eff))
    #= The default min_X result in:
        abs(exp(im*min_X*cos(θ_effs[end])*k_effs[end]/k)) < tol
    =#
    # estimate a reasonable derivative based on more rapidly varying wave_eff_short.
    df = abs(wave_eff_short.k_eff * cos(wave_eff_short.θ_eff))

    # Based on Simpson's rule
        # dX  = (tol*90 / (df^4))^(1/5)
    # Based on trapezoidal integration
        dx  = (tol * 30 / (df^2))^(1/3)

    # if whole correction length a12k was given, then make dX/a12k = integer
    if a12  != zero(T)
        n = ceil(a12 / dx)
        dx = a12/n
    end

    return 0:dx:max_x
end
