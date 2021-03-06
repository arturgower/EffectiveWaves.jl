"Calculates the effective wavenumbers and return Vector{EffectivePlaneWaveMode}."
function WaveModes(ω::T, source::AbstractSource, material::Material{Dim,S,Sps}; kws...) where {T,Dim,S<:Shape{T,Dim},Sps<:Species{T,Dim}} # without the parametric types we get a "Unreachable reached" error

    # The wavenumbers are calculated without knowledge of the materail symmetry. This is because the plane-wave symmetry leads to all possible wavenumbers and is simple to calculate.
    k_effs = wavenumbers(ω, source.medium, material.species; kws... )

    # The wavemodes need to know the material symmetry as the eigenvectors do depend on material shape and symetry.
    wave_effs = [
        WaveMode(ω, k_eff, source, material; kws...)
    for k_eff in k_effs]

    return wave_effs
end

"""
    WaveMode(ω::T, wavenumber::Complex{T}, eigenvectors::Array{Complex{T}}, ::SetupSymmetry; kws...)

Returns a concrete subtype of AbstractWaveMode depending on the SetupSymmetry. The returned type should have all the necessary fields to calculate scattered waves (currently not true for EffectivePlanarWaves).
"""
function WaveMode(ω::T, wavenumber::Complex{T}, source::AbstractSource{T}, material::Material{Dim}; kws...) where {T,Dim}

    eigvectors = eigenvectors(ω, wavenumber, source, material; kws...)

    α = solve_boundary_condition(ω, wavenumber, eigvectors, source, material; kws...)

    # After this normalisation, sum(eigvectors, dims = 3) will satisfy the boundary conditions
    eigvectors = [eigvectors[i] * α[i[3]] for i in CartesianIndices(eigvectors)]

    return EffectiveRegularWaveMode(ω, wavenumber, source, material, eigvectors; kws...)
end

function WaveMode(ω::T, wavenumber::Complex{T}, psource::PlaneSource{T,Dim,1}, material::Material{Dim,Halfspace{T,Dim}};
    tol::T = 1e-6, kws...) where {T,Dim}

    direction = transmission_direction(wavenumber, (ω / psource.medium.c) * psource.direction, material.shape.normal)
    eigvectors = eigenvectors(ω, wavenumber, psource, material; direction_eff = direction, kws...)

    α = solve_boundary_condition(ω, wavenumber, eigvectors, psource, material; kws...)

    # After this normalisation, sum(eigvectors, dims = 3) will satisfy the boundary conditions
    eigvectors = [eigvectors[i] * α[i[3]] for i in CartesianIndices(eigvectors)]

    return EffectivePlaneWaveMode(ω, wavenumber, direction, eigvectors)
end

function WaveMode(ω::T, wavenumber::Complex{T}, psource::PlaneSource{T,Dim,1}, material::Material{Dim,Plate{T,Dim}}; kws...) where {T,Dim}

    direction1 = transmission_direction(wavenumber, (ω / psource.medium.c) * psource.direction, material.shape.normal)
    eigvectors1 = eigenvectors(ω, wavenumber, psource, material; direction_eff = direction1, kws...)

    # looks like we always have eigvectors2 = eigvectors1, but I haven't proven this yet.
    direction2 = transmission_direction(- wavenumber, (ω / psource.medium.c) * psource.direction, material.shape.normal)
    eigvectors2 = eigenvectors(ω, - wavenumber, psource, material; direction_eff = direction2, kws...)

    α = solve_boundary_condition(ω, wavenumber, eigvectors1, eigvectors2, psource, material; kws...)

    # apply normalisation
    eigvectors1 = eigvectors1 .* α[1]
    eigvectors2 = eigvectors2 .* α[2]

    mode1 = EffectivePlaneWaveMode(ω, wavenumber, direction1, eigvectors1)
    mode2 = EffectivePlaneWaveMode(ω, - wavenumber, direction2, eigvectors2)

    return [mode1,mode2]
end

# eigensystem(ω::T, source::AbstractSource{T}, material::Material; kws...) where T<:AbstractFloat = eigensystem(ω, source.medium, material.species, setupsymmetry(source,material); numberofparticles = material.numberofparticles, kws...)

eigenvectors(ω::T, k_eff::Complex{T}, source::AbstractSource{T}, material::Material; kws...) where T<:AbstractFloat = eigenvectors(ω, k_eff::Complex{T}, source.medium, material.species, setupsymmetry(source,material); numberofparticles = material.numberofparticles, kws...)

# For plane waves, it is simpler to write all cases in the format for the most general case. For example, for PlanarAzimuthalSymmetry the eignvectors are much smaller. So we will turn these into the more general eigvector case by padding it with zeros.
function eigenvectors(ω::T, k_eff::Complex{T}, source::PlaneSource{T}, material::Material{Dim,S}; kws...) where {T<:AbstractFloat,Dim,S<:Union{Plate,Halfspace}}

    eigvecs = eigenvectors(ω, k_eff, source.medium, material.species, setupsymmetry(source,material); kws...)

    if setupsymmetry(source,material) == PlanarAzimuthalSymmetry{Dim}()
        eigvecs = azimuthal_to_planar_eigenvector(typeof(source.medium),eigvecs)
    end

    return eigvecs

end

function eigenvectors(ω::T, k_eff::Complex{T}, medium::PhysicalMedium{T}, species::Vector{Sp}, symmetry::AbstractSetupSymmetry;
        tol::T = 1e-4, kws...
    ) where {T<:AbstractFloat, Sp<:Specie{T}}

    MM = eigensystem(ω, medium, species, symmetry; kws...)

    # calculate eigenvectors
    MM_svd = svd(MM(k_eff))
    inds = findall(MM_svd.S .< tol)

    if isempty(inds)
        @warn("No eigenvectors found with the tolerance tol = $tol. Will use only one eigenvector with the eigenvalue $(MM_svd.S[end]), which should be less than tol.")
        inds = [length(MM_svd.S)]
    end

    #NOTE: MM(k_eff) ≈ MM_svd.U * diagm(0 => MM_svd.S) * MM_svd.Vt
    eigvectors = MM_svd.V[:,inds]

    # Reshape to separate different species and eigenvectors
    S = length(species)

    return reshape(eigvectors,(:,S,size(eigvectors,2)))
end
