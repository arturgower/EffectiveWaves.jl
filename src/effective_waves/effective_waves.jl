"A type for the effective wave ansatz."
type EffectiveWave{T<:Real}
    hankel_order::Int
    amplitudes::Array{Complex{T}} # the effective ampliudes
    k_eff::Complex{T} # the effective wavenumber
    θ_eff::Complex{T} # the effective transmission angle
end

function EffectiveWave(ω::T, k_eff::Complex{T}, medium::Medium{T}, species::Vector{Specie{T}};
        θin::T = 0.0, tol = 1e-8, extinction_rescale = true, kws...) where T<:AbstractFloat

    k = ω/medium.c
    θ_eff = transmission_angle(k, k_eff, θin; tol = tol)
    amps = reduced_amplitudes_effective(ω, k_eff, medium, species; tol = tol, kws...)
    hankel_order = Int(size(amps,1)/2-1/2)
    wave_eff = EffectiveWave(hankel_order, amps, k_eff, θ_eff)

    if extinction_rescale
        amps = amps.*scale_amplitudes_effective(ω, wave_eff, medium, species; tol = tol, θin=θin)
    end

    return EffectiveWave(hankel_order, amps, k_eff, θ_eff)
end


"The average effective transmitted scattering amplitudes for a given effective wavenumber k_eff. Assumes there exists only one k_eff.
The function returns an array A, where
AA(x,y,m,s) = im^m*exp(-im*m*θ_eff)*A[m + max_hankel_order +1,s]*exp(im*k_eff*(cos(θ_eff)*x + sin(θin)*y))
where (x,y) are coordinates in the halfspace, m-th hankel order, s-th species,  and AA is the ensemble average scattering coefficient."
function reduced_amplitudes_effective(ω::T, k_eff::Complex{T}, medium::Medium{T}, species::Vector{Specie{T}};
            tol = 1e-5,
            radius_multiplier = 1.005,
            hankel_order = maximum_hankel_order(ω, medium, species; tol=tol)
            ) where T<:Number

        k = ω/medium.c
        S = length(species)
        ho = hankel_order

        as = radius_multiplier*[(s1.r + s2.r) for s1 in species, s2 in species]
        function MM(keff,j,l,m,n)
            (n==m ? 1.0:0.0)*(j==l ? 1.0:0.0) + 2.0pi*species[l].num_density*Zn(ω,species[l],medium,n)*
                Nn(n-m,k*as[j,l],keff*as[j,l])/(k^2.0-keff^2.0)
        end

        # calculate effective amplitudes
        MM_svd = svd(
            reshape(
                [MM(k_eff,j,l,m,n) for m in -ho:ho, j in 1:S, n in -ho:ho, l in 1:S]
            , ((2ho+1)*S, (2ho+1)*S))
        )
        if MM_svd[2][end] > T(10)*tol
            warn("The effective wavenumber gave an eigenvalue $(MM_svd[2][end]), which is larger than the tol = $( T(10)*tol). Note the secular equation is determined by the chosen medium and species.")
        end

        A_null = MM_svd[3][:,end] # eignvector of smallest eigenvalue
        A_null = reshape(A_null, (2*ho+1,S)) # A_null[:,j] = [A[-ho,j],A[-ho+1,j],...,A[ho,j]]

        return A_null
end

"returns a number a, such that a*As_eff will cancel an incident wave plane wave with incident angle θin."
function scale_amplitudes_effective(ω::T, wave_eff::EffectiveWave{T},
        medium::Medium{T}, species::Vector{Specie{T}};
        θin::T = 0.0, tol = 1e-8) where T<:Number

    k = ω/medium.c
    θ_eff = wave_eff.θ_eff
    ho = wave_eff.hankel_order
    amps = wave_eff.amplitudes
    S = length(species)

    sumAs = T(2)*sum(
            exp(im*n*(θin - θ_eff))*Zn(ω,species[l],medium,n)*species[l].num_density*amps[n+ho+1,l]
    for n = -ho:ho, l = 1:S)
    a = im*k*cos(θin)*(wave_eff.k_eff*cos(θ_eff) - k*cos(θin))/sumAs

    return a
end