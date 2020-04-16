function boundary_condition_system(ω::T, k_eff::Complex{T}, source::AbstractSource{T,Dim,1,Acoustic{T,Dim}}, material::Material{Dim,Sphere{T,Dim}};
        basis_order::Int = 2,
        basis_field_order::Int = 4,
        kws...
    ) where {T<:Number,Dim}

    k = real(ω / source.medium.c)

    Ns = [
        kernelN3D(l3,k*R,keff*R)
    for l3 = 0:basis_field_order] ./ (k^T(2) - keff^T(2))

    extinction_matrix = T(2) .* transpose(vec(
        [
            exp(im*n*(θin - θ_eff)) * number_density(s)
        for n = -ho:ho, s in material.species]
    ))

    forcing = [im * field(psource,zeros(T,Dim),ω) * kcos_in * (kcos_eff - kcos_in)]

    return extinction_matrix, forcing

end

function effective_wavemode(ω::T, k_eff::Complex{T}, source::Source{T,Acoustic{T,Dim}}, material::Material{Dim,Sphere{T}};
        tol::T = 1e-6, kws...
    ) where {T<:AbstractFloat,Dim}

    k = ω/psource.medium.c

    direction = transmission_direction(k_eff, (ω / psource.medium.c) * psource.direction, material.shape.normal; tol = tol)

    amps = eigenvectors(ω, k_eff, psource, material; tol= tol)

    return EffectiveRegularWaveMode(ω, k_eff, direction, amps)
end