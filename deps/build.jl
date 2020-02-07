using CxxWrap
using BinaryProvider
using Base.Filesystem
import Pkg
import CMake

# Parse some basic command-line arguments
const verbose = "--verbose" in ARGS

# Dependencies that must be installed before this package can be built
dependencies = [
    "https://github.com/JuliaPackaging/Yggdrasil/releases/download/MPFR-v4.0.2-1/build_MPFR.v4.0.2.jl",
    "https://github.com/JuliaPackaging/Yggdrasil/releases/download/GMP-v6.1.2-1/build_GMP.v6.1.2.jl",
    "https://github.com/benlorenz/ncursesBuilder/releases/download/v6.1/build_ncurses.v6.1.0.jl",
    "https://github.com/benlorenz/readlineBuilder/releases/download/v8.0/build_readline.v8.0.0.jl",
    "https://github.com/benlorenz/perlBuilder/releases/download/v5.30.0-2/build_perl.v5.30.0.jl",
    "https://github.com/benlorenz/boostBuilder/releases/download/v1.71.0/build_boost.v1.71.0.jl",
    "https://github.com/benlorenz/pplBuilder/releases/download/v1.2/build_ppl.v1.2.0.jl",
    "https://github.com/benlorenz/lrslibBuilder/releases/download/v7.0/build_lrslib.v7.0.0.jl",
    "https://github.com/benlorenz/cddlibBuilder/releases/download/v0.94.0-j-1/build_cddlib.v0.94.0-j.jl",
    "https://github.com/benlorenz/blissBuilder/releases/download/v0.73/build_bliss.v0.73.0.jl",
    "https://github.com/benlorenz/normalizBuilder/releases/download/v3.7.4/build_normaliz.v3.7.4.jl",
    "https://github.com/benlorenz/ninjaBuilder/releases/download/v1.9.0/build_ninja.v1.9.0.jl",
    "https://github.com/thofma/Flint2Builder/releases/download/ba0cee/build_libflint.v0.0.0-ba0ceed35136a2a43441ab9a9b2e7764e38548ea.jl",
    "https://github.com/thofma/NTLBuilder2/releases/download/v10.5.0-1/build_libntl.v10.5.0.jl",
    "https://github.com/wbhart/SingularBuilder/releases/download/v0.0.1/build_libsingular.v0.0.1.jl",
]


pm_config = joinpath(@__DIR__,"usr","bin","polymake-config")
perl = joinpath(@__DIR__,"usr","bin","perl")
use_binary = true
depsjl = ""

if !( haskey(ENV, "POLYMAKE_CONFIG") && ENV["POLYMAKE_CONFIG"] == "no" )
    try
        # test whether polymake config is available in path
        global pm_config = chomp(read(`command -v polymake-config`, String))
        global perl ="perl"
        global use_binary = false
    catch
        if haskey(ENV, "POLYMAKE_CONFIG")
            global pm_config = ENV["POLYMAKE_CONFIG"]
            global perl ="perl"
            global use_binary = false
        end
    end
end

const prefix = Prefix(joinpath(dirname(pm_config),".."))
const polymake = joinpath(prefix,"bin","polymake")

products = Product[
    LibraryProduct(prefix, "libpolymake", :libpolymake)
    ExecutableProduct(prefix,"polymake", :polymake)
    ExecutableProduct(prefix,"polymake-config", Symbol("polymake_config"))
    ExecutableProduct(prefix,"ninja", :ninja)
    ExecutableProduct(prefix,"perl", :perl)
]

# Download binaries from hosted location
bin_prefix = "https://github.com/benlorenz/polymakeBuilder/releases/download/v4.0"

# Listing of files generated by BinaryBuilder:
download_info = Dict(
    MacOS(:x86_64) => ("$bin_prefix/polymake.v4.0.0.x86_64-apple-darwin14.tar.gz", "ebbed96463f43641ec7dbf24fbb81fdde1c5a6931725e13f85778015529d241a"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc6)) => ("$bin_prefix/polymake.v4.0.0.x86_64-linux-gnu-gcc6.tar.gz", "1d30e02e71e91dfdebeb8b6a36b53d05124dda2f2b86c827596af03ab5ab88ca"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/polymake.v4.0.0.x86_64-linux-gnu-gcc7.tar.gz", "21dfb7efd806dbae7b79f49486ec7e6157c5ce23d55b653ee45f4cac8cb84bf5"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/polymake.v4.0.0.x86_64-linux-gnu-gcc8.tar.gz", "3d490705c37085ee429ff9a95d216585292d3f2b937e31f36edcce52c2287669"),
)

if use_binary
    # Install unsatisfied or updated dependencies:
    unsatisfied = any(!satisfied(p; verbose=verbose) for p in products)
    dl_info = choose_download(download_info, platform_key_abi())
    platform = platform_key_abi()
    @info platform
    if dl_info === nothing && unsatisfied
        # If we don't have a BinaryProvider-compatible .tar.gz to download, complain.
        # Alternatively, you could attempt to install from a separate provider,
        # build from source or something even more ambitious here.
        error("""
Your platform $(triplet(platform)) is not supported by this package!
If you already have a polymake installation you need to set the environment variable `POLYMAKE_CONFIG`.
""")
    end
    if unsatisfied || !isinstalled(dl_info...; prefix=prefix)
        # Download and install binaries
        for dependency in dependencies          # We do not check for already installed dependencies
            download(dependency,basename(dependency))
            evalfile(basename(dependency))
        end
        install(dl_info...; prefix=prefix, force=true, verbose=verbose)
    end
    pm_config_ninja = joinpath(libdir(prefix),"polymake","config.ninja")
    pm_bin_prefix = joinpath(@__DIR__,"usr")
    perllib = replace(chomp(read(`$perl -e 'print join(":",@INC);'`,String)),"/workspace/destdir/"=>prefix.path)
    global depsjl = quote
        using Pkg: depots1
        function prepare_env()
            ENV["PERL5LIB"]=$perllib
            user_dir = ENV["POLYMAKE_USER_DIR"] = abspath(joinpath(depots1(),"polymake_user"))
            if Base.Filesystem.isdir(user_dir)
                del = filter(i -> Base.Filesystem.isdir(i) && startswith(i, "wrappers."), readdir(user_dir))
                for i in del
                    Base.Filesystem.rm(user_dir * "/" * i, recursive = true)
                end
            end
            ENV["PATH"] = ENV["PATH"]*":"*$pm_bin_prefix*"/bin"
        end
    end
    eval(depsjl)
    prepare_env()
    run(`$perl -pi -e "s{REPLACEPREFIX}{$pm_bin_prefix}g" $pm_config $pm_config_ninja $polymake`)
    run(`sh -c "$perl -pi -e 's{/workspace/destdir}{$pm_bin_prefix}g' $pm_bin_prefix/lib/perl5/*/*/Config_heavy.pl"`)

else
    if pm_config == nothing
        error("Set `POLYMAKE_CONFIG` ENV variable. And rebuild Polymake by calling `import Pkg; Pkg.build(\"Polymake\")`.")
    end
end

minimal_polymake_version = v"4.0"

pm_version = read(`$perl $pm_config --version`, String) |> chomp |> VersionNumber
if pm_version < minimal_polymake_version
    error("Polymake version $pm_version is older than minimal required version $minimal_polymake_version")
end

pm_include_statements = read(`$perl $pm_config --includes`, String) |> chomp |> split
# Remove the -I prefix of all includes
pm_include_statements = map(i -> i[3:end], pm_include_statements)
push!(pm_include_statements, joinpath(pm_include_statements[1],"..","share","polymake"))
pm_includes = join(pm_include_statements, " ")

pm_cflags = chomp(read(`$perl $pm_config --cflags`, String))
pm_ldflags = chomp(read(`$perl $pm_config --ldflags`, String))
pm_libraries = chomp(read(`$perl $pm_config --libs`, String))
pm_cxx = chomp(read(`$perl $pm_config --cc`, String))

jlcxx_cmake_dir = joinpath(dirname(CxxWrap.jlcxx_path), "cmake", "JlCxx")

julia_exec = joinpath(Sys.BINDIR , "julia")

cd(joinpath(@__DIR__, "src"))

include("type_setup.jl")

run(`$(CMake.cmake) -DJulia_EXECUTABLE=$julia_exec -DJlCxx_DIR=$jlcxx_cmake_dir -Dpolymake_includes=$pm_includes -Dpolymake_ldflags=$pm_ldflags -Dpolymake_libs=$pm_libraries -Dpolymake_cflags=$pm_cflags -DCMAKE_CXX_COMPILER=$pm_cxx  -DCMAKE_INSTALL_LIBDIR=lib .`)
cpus = max(div(Sys.CPU_THREADS,2), 1)
run(`make -j$cpus`)

json_script = joinpath(@__DIR__,"rules","apptojson.pl")
json_folder = joinpath(@__DIR__,"json")
mkpath(json_folder)

run(`$perl $polymake --iscript $json_script $json_folder`)

# remove old deps.jl first to avoid problems when switching from binary installation
rm(joinpath(@__DIR__,"deps.jl"), force=true)

if use_binary
    # Write out a deps.jl file that will contain mappings for our products
    write_deps_file(joinpath(@__DIR__, "deps.jl"), products, verbose=verbose)
end

println("appending to deps.jl file")
open(joinpath(@__DIR__,"deps.jl"), "a") do f
   println(f, "const using_binary = $use_binary")
   println(f, depsjl)
end
