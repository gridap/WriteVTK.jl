function vtk_grid(dtype::VTKRectilinearGrid, filename::AbstractString,
                  x::AbstractVector, y::AbstractVector, z::AbstractVector;
                  extent=nothing, kwargs...)
    Ni, Nj, Nk = length(x), length(y), length(z)
    Npts = Ni*Nj*Nk
    Ncls = num_cells_structured(Ni, Nj, Nk)
    ext = extent_attribute(Ni, Nj, Nk, extent)

    xvtk = XMLDocument()
    vtk = DatasetFile(dtype, xvtk, filename, Npts, Ncls; kwargs...)

    # VTKFile node
    xroot = vtk_xml_write_header(vtk)

    # RectilinearGrid node
    xGrid = new_child(xroot, vtk.grid_type)
    set_attribute(xGrid, "WholeExtent", ext)

    # Piece node
    xPiece = new_child(xGrid, "Piece")
    set_attribute(xPiece, "Extent", ext)

    # Coordinates node
    xPoints = new_child(xPiece, "Coordinates")

    # DataArray node
    data_to_xml(vtk, xPoints, x, "x")
    data_to_xml(vtk, xPoints, y, "y")
    data_to_xml(vtk, xPoints, z, "z")

    vtk
end

"""
    vtk_grid(filename::AbstractString,
             x::AbstractVector{T}, y::AbstractVector{T}, [z::AbstractVector{T}];
             kwargs...)

Create 2D or 3D rectilinear grid (`.vtr`) file.

Coordinates are specified by separate vectors `x`, `y`, `z`.

# Examples

```jldoctest
julia> vtk = vtk_grid("abc", [0., 0.2, 0.5], collect(-2.:0.2:3), [1., 2.1, 2.3])
VTK file 'abc.vtr' (RectilinearGrid file, open)
```

"""
vtk_grid(filename::AbstractString, x::AbstractVector{T},
         y::AbstractVector{T}, z::AbstractVector{T}; kwargs...) where T =
    vtk_grid(VTKRectilinearGrid(), filename, x, y, z; kwargs...)

# 2D variant
vtk_grid(filename::AbstractString, x::AbstractVector{T},
         y::AbstractVector{T}; kwargs...) where T =
    vtk_grid(VTKRectilinearGrid(), filename, x, y, Zeros{T}(1); kwargs...)
