export generate_test_problems, generate_noisy_data!,
    generate_noisy_data, generate_clustered_noisy_data,
    generate_clustered_noisy_data!

"""

This dictionary represents the list of models used in the generation of random tests.
Return the tuple `(n, model, model_str)`, where

  - `n` is the number of parameters of the model
  - `model` is the model of the form `m(x, θ)`, where `x` are the
    variables and `θ` are the parameters
  - `model_str` is the string representing the model, used to build random generated problems

"""
const model_list = Dict(
    "linear" => (2, (x, θ) -> θ[1] * x[1] + θ[2],
                 "(x, θ) -> θ[1] * x[1] + θ[2]"),
    "cubic" => (4, (x, θ) -> θ[1] * x[1]^3 + θ[2] * x[1]^2 + θ[3] * x[1] + θ[4],
                "(x, θ) -> θ[1] * x[1]^3 + θ[2] * x[1]^2 + θ[3] * x[1] + θ[4]"),
    "expon" => (3, (x, θ) -> θ[1] + θ[2] * exp(- θ[3] * x[1]),
                "(x, θ) -> θ[1] + θ[2] * exp(- θ[3] * x[1])"),
    "logistic" => (4, (x, θ) -> θ[1] + θ[2] / (1.0 + exp(- θ[3] * x[1] + θ[4])),
                   "(x, θ) -> θ[1] + θ[2] / (1.0 + exp(- θ[3] * x[1] + θ[4]))"),
    "circle" => (3, (x, θ) -> (x[1] - θ[1])^2 + (x[2] - θ[2])^2 - θ[3]^2,
                 "(x, θ) -> (x[1] - θ[1])^2 + (x[2] - θ[2])^2 - θ[3]^2")
)


"""

    generate_test_problems(datFilename::String, solFilename::String,
                         model::Function, modelStr::String, n::Int,
                         np::Int, p::Int; xMin=-10.0, xMax=10.0,
                         θSol=10.0 * randn(n), std=200.0, out_times=7.0)

Generate random data files for testing fitting problems.

  - `datFilename` and `solFilename` are strings with the name of the
    files for storing the random data and solution, respectively.
  - `model` is the model function and `modelStr` is a string
    representing this model function, e.g.

         model = (x, θ) -> θ[1] * x[1] + θ[2]
         modelStr = "(x, θ) -> θ[1] * x[1] + θ[2]"

    where vector `θ` represents the parameters (to be found) of the
    model and vector `x` are the variables of the model.
  - `n` is the number of parameters
  - `np` is the number of points to be generated.
  - `p` is the number of trusted points to be used in the LOVO
    approach.

Additional parameters:

  - `xMin`, `xMax`: minimum and maximum interval for generating points
    in one dimensional tests
  - `θSol`: true solution, used for generating perturbed points
  - `std`: standard deviation
  - `out_times`: deviation for outliers will be `out_times * std`.

"""
function generate_test_problems(datFilename::String,
                              solFilename::String, model::Function,
                              modelStr::String,
                              n::Int, np::Int, p::Int;
                              xMin=-10.0, xMax=10.0,
                              θSol=10.0 * randn(n), std=200.0, out_times=7.0)

    # Generate solution file
    
    open(solFilename, "w") do sol
    
        println(sol, n) # number of variables

        println(sol, θSol) # parameters
        
        println(sol, modelStr) # function expression

    end

    # Generate data file
    
    open(datFilename, "w") do data
    
        vdata, θsol, outliers = generate_noisy_data(model, n, np, p;
                                   xMin=xMin, xMax=xMax, θSol=θSol,
                                   std=std, out_times=out_times)
    
        # Dimension of the domain of the function to fit
        @printf(data, "%d\n", 1)

        for k = 1:np

            @printf(data, "%20.15f %20.15f %1d\n",
                    vdata[k, 1], vdata[k, 2], Int(k in outliers))

        end

    end
    
end

"""

    get_unique_random_points(np::Int, npp::Int)

Choose exactly `npp` unique random points from a set containing `np`
points. This function is similar to `rand(vector)`, but does not allow
repetitions.

If `npp` < `np`, returns all the `np` points. Note that this function
is not very memory efficient, since the process of selecting unique
elements involves creating several temporary vectors.

Return a vector with the selected points.

"""
function get_unique_random_points(np::Int, npp::Int)

    # Check invalid arguments
    ((np <= 0) || (npp <=0)) && (return Vector{Int}())

    ntp = min(npp, np)
    
    v = Vector{Int}(undef, ntp)
    
    return get_unique_random_points!(v, np, npp)

end

"""

    get_unique_random_points!(v::Vector{Int}, np::Int, npp::Int)

Choose exactly `npp` unique random points from a set containing `np`
points. This function is similar to `rand(vector)`, but does not allow
repetitions.

If `npp` < `np`, returns all the `np` points. Note that this function
is not very memory efficient, since the process of selecting unique
elements involves creating several temporary vectors.

Return the vector `v` provided as argument filled with the selected
points.

"""
function get_unique_random_points!(v::Vector{Int}, np::Int, npp::Int)

    # Check invalid arguments
    ((np <= 0) || (npp <=0)) && return v

    ntp = min(np, npp)
    
    # Check invalid size
    (length(v) < ntp) && throw(DimensionMismatch("Incorrect size for vector."))
    
    # Check small np for efficiency
    if np == ntp

        for i = 1:np
            v[i] = i
        end

        return v

    end

    points = [1:np;]

    while ntp > 0
        
        u = rand(points, ntp)

        unique!(u)

        for i in u
            v[ntp] = i
            ntp -= 1
        end

        setdiff!(points, u)
        
    end

    return v

end

"""

    generate_noisy_data(model::Function, n::Int, np::Int, p::Int;
                      xMin::Float64=-10.0, xMax::Float64=10.0,
                      θSol::Vector{Float64}=10.0 * randn(Float64, n),
                      std::Float64=200.0, out_times::Float64=7.0)

    generate_noisy_data(model::Function, n, np, p, xMin::Float64, xMax::Float64)

    generate_noisy_data(model::Function, n::Int, np::Int, p::Int,
                      θSol::Vector{Float64}, xMin::Float64, xMax::Float64)

Random generate a fitting one-dimensional data problem.

This function receives a `model(x, θ)` function, the number of parameters
`n`, the number of points `np` to be generated and the number of
trusted points `p`. 

If the `n`-dimensional vector `θSol` is provided, then the exact
solution will not be random generated. The interval `[xMin, xMax]` for
generating the values to evaluate `model` can also be provided.

It returns a tuple `(data, θSol, outliers)` where

  - `data`: (`np` x `2`) array, where each row contains `x` and
    `model(x, θSol)`.
  - `θSol`: `n`-dimensional vector with the exact solution.
  - `outliers`: the outliers of this data set

"""
function generate_noisy_data(model::Function, n::Int, np::Int, p::Int;
                           xMin::Float64=-10.0, xMax::Float64=10.0,
                           θSol::Vector{Float64}=10.0 * randn(Float64, n),
                           std::Float64=200.0, out_times::Float64=7.0)

    # Data matrix
    data = Array{Float64}(undef, np, 3)

    # Points selected to be outliers
    v = Vector{Int}(undef, np - p)

    return generate_noisy_data!(data, v, model, n, np, p; xMin=xMin, xMax=xMax,
                                θSol=θSol, std=std, out_times=out_times)
    
end

generate_noisy_data(model::Function, n::Int, np::Int, p::Int, xMin::Float64, xMax::Float64) =
    generate_noisy_data(model, n, np, p; xMin=xMin, xMax=xMax)

generate_noisy_data(model::Function, n::Int, np::Int, p::Int,
                  θSol::Vector{Float64}, xMin::Float64, xMax::Float64) =
                      generate_noisy_data(model, n, np, p; xMin=xMin, xMax=xMax, θSol=θSol)

"""

    generate_noisy_data!(data::Array{Float64, 2}, v::Vector{Int},
           model::Function, n::Int, np::Int, p::Int;
           xMin::Float64=-10.0, xMax::Float64=10.0,
           θSol::Vector{Float64}=10.0 * randn(Float64, n),
           std::Float64=200.0, out_times::Float64=7.0)

    generate_noisy_data!(model::Function, n, np, p, xMin::Float64, xMax::Float64)

    generate_noisy_data!(model::Function, n::Int, np::Int, p::Int,
                      θSol::Vector{Float64}, xMin::Float64, xMax::Float64)

Random generate a fitting one-dimensional data problem, storing the
data in matrix `data` and the outliers in vector `v`.

This function receives a `model(x, θ)` function, the number of parameters
`n`, the number of points `np` to be generated and the number of
trusted points `p`. 

If the `n`-dimensional vector `θSol` is provided, then the exact
solution will not be random generated. The interval `[xMin, xMax]` for
generating the values to evaluate `model` can also be provided.

It returns a tuple `(data, θSol, outliers)` where

  - `data`: (`np` x `2`) array, where each row contains `x` and
    `model(x, θSol)`.
  - `θSol`: `n`-dimensional vector with the exact solution.
  - `outliers`: the outliers of this data set

"""
function generate_noisy_data!(data::Union{SubArray, Array{Float64, 2}},
           v::Vector{Int}, model::Function, n::Int, np::Int, p::Int;
           xMin::Float64=-10.0, xMax::Float64=10.0,
           θSol::Vector{Float64}=10.0 * randn(Float64, n),
           std::Float64=200.0, out_times::Float64=7.0)

    @assert(xMin <= xMax, "Invalid interval for random number generation.")
    @assert(size(data) == (np, 3), "Invalid size of data matrix. $(size(data)) != $((np, 3)).")
    @assert(length(v) >= np - p, "Invalid size for vector of outliers.")
    
    # Generate (xi,yi) where xMin <= x_i <= xMax (data)
    x = LinRange(xMin, xMax, np)
    
    # Points selected to be outliers
    get_unique_random_points!(v, np, np - p)
    
    # Add noise to some random points
    for k = 1:np
            
        y = model(x[k], θSol) + randn() * std

        noise = 0.0
            
        if k in v 
            y = model(x[k], θSol)
            noise = (1.0 + 2 * rand()) * out_times * std * sign(randn())
        end
            
        data[k, 1] = x[k]
        data[k, 2] = y + noise
        data[k, 3] = noise

    end

    return data, θSol, v

end

function generate_clustered_noisy_data(model::Function, n::Int,
            np::Int, p::Int, x_interval::Tuple{Float64,Float64},
            cluster_interval::Tuple{Float64, Float64})

    data = Array{Float64, 2}(undef, np, 3)

    v = Vector{Int}(undef, np - p)

    return generate_clustered_noisy_data!(data, v, model, n, np, p,
               x_interval, cluster_interval)

end

"""

Generate a test set with clustered outliers. The arguments are the
same for [generate_noisy_data](@ref), with exception of tuple
`cluster_interval` which is the interval to generate the clustered
outliers.

"""
function generate_clustered_noisy_data!(data::Array{Float64, 2},
            v::Vector{Int}, model::Function, n::Int, np::Int,
            p::Int, x_interval::Tuple{Float64,Float64},
            cluster_interval::Tuple{Float64, Float64};
            θSol::Vector{Float64}=10.0 * randn(Float64, n))

    if !(x_interval[1] <= cluster_interval[1] < cluster_interval[2] <=
         x_interval[2])

        error("Bad interval for data generation.")

    end
    
    interval_len = x_interval[2] - x_interval[1]
 
    fr1 = (cluster_interval[1] - x_interval[1]) / interval_len
    fr2 = (cluster_interval[2] - cluster_interval[1]) / interval_len
    fr3 = (x_interval[2] - cluster_interval[2]) / interval_len

    # Distribute data in a proportional way
    
    # Interval 2 will contain the clustered outliers
    np2 = max(np - p, Int(round(fr2 * np)))
    np1 = max(np - np2, Int(round(fr1 * np)))
    # Interval 3 will contain the remaining points
    np3 = max(0, np - np1 - np2)

    @debug("Clustered points: $(np1), $(np2), $(np3).")
    
    # Generate data

    tmpv = Vector{Int}()
    
    generate_noisy_data!(@view(data[1:np1, :]), tmpv, model, n, np1,
        np1; θSol=θSol, xMin=x_interval[1], xMax=cluster_interval[1])

    generate_noisy_data!(@view(data[np1 + 1:np1 + np2, :]), v, model,
        n, np2, np2 - (np - p); θSol=θSol, xMin=cluster_interval[1],
        xMax=cluster_interval[2])

    # Update the outlier number with the correct number
    map!((x) -> x + np2, v, v)
    
    generate_noisy_data!(@view(data[np1 + np2 + 1:np, :]), tmpv, model,
        n, np3, np3; θSol=θSol, xMin=cluster_interval[2],
        xMax=x_interval[2])

    return data, θSol, v
    
end
