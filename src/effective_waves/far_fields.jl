# Before far field patterns and the pair field patterns are calculated here. These are needed for the effective wavenumber and reflection for low volume fraction.

d(x,m) = diffbesselj(m,x)*diffhankelh1(m,x) + (1.0 - (m/x)^2)*besselj(m,x)*hankelh1(m,x)

function far_field_pattern(ω::T, medium::Acoustic{T,2}, species::Vector{Specie{T}}; tol=1e-6, basis_order = 2, #maximum_basis_order(ω, medium, species; tol=tol),
        verbose = false, kws...) where T<:Number

    if verbose
        println("$basis_order was the largest hankel order used for the far field pattern")
    end
    Zs = - get_t_matrices(medium, species, ω, basis_order)
    # Zs = Zn_matrix(ω, medium, species; basis_order = basis_order)
    num_density_inv = one(T)/sum(number_density.(species))

    far_field(θ::T) where T <: Number = -num_density_inv*sum(
        number_density(species[i])*Zs[i][n,n]*exp(im*θ*n)
    for i in eachindex(species), n=-basis_order:basis_order)

    return far_field
end

function diff_far_field_pattern(ω::T, medium::Acoustic{T,2}, species::Vector{Specie{T}}; tol=1e-6, basis_order = 2, #maximum_basis_order(ω, medium, species; tol=tol),
        verbose = false, kws...) where T<:Number

    if verbose
        println("$basis_order was the largest hankel order used for the far field pattern")
    end
    Zs = - get_t_matrices(medium, species, ω, basis_order)
    # Zs = Zn_matrix(ω, medium, species; basis_order = basis_order)
    num_density_inv = one(T) / sum(number_density.(species))

    far_field(θ::T) where T <: Number = -num_density_inv*sum(
        number_density(species[i])*Zs[i][n,n]*im*n*exp(im*θ*n)
    for i in eachindex(species), n=-basis_order:basis_order)

    return far_field
end

function pair_field_pattern(ω::T, medium::Acoustic{T,2}, species::Vector{Specie{T}}; tol::T = T(1e-6),
        basis_order = 2, #maximum_basis_order(ω, medium, species; tol=tol),
        # radius_multiplier = T(1.005),
        verbose = false, kws...) where T<:Number

    # Zs = Zn_matrix(ω, medium, species; basis_order = basis_order)
    Zs = - get_t_matrices(medium, species, ω, basis_order)

    num_density_inv = one(T)/sum(number_density.(sp))

    pair_field(θ::T) where T <: Number = -T(π)*num_density_inv^(2.0)*sum(
        begin
            a12 = radius_multiplier*(outer_radius(species[i]) * species[i].exclusion_distance + outer_radius(species[j]) * species[j].exclusion_distance )
            number_density(species[i]) * number_density(species[j]) * a12^2.0 * d(a12*ω/medium.c,m-n)*Zs[i][n,n]*Zs[j][m,m]*exp(im*m*θ)
        end
    for i=1:length(species), j=1:length(species),
    n = -basis_order:basis_order, m = -basis_order:basis_order)

    return pair_field
end
