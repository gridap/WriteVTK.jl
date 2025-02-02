# Helper types

struct PVTKArgs
  part::Int
  nparts::Int
  ismain::Bool
  ghost_level::Int
end

struct PVTKFile <: VTKFile
  pvtkargs::PVTKArgs
  xdoc::XMLDocument
  vtk::DatasetFile
  path::String
end

# Main functions

"""
    pvtk_grid(args...;
              part,
              nparts,
              ismain = (part == 1),
              ghost_level = 0,
              kwargs...)

Return a handler representing a parallel vtk file, which can be
eventually written to file with `vtk_save`.

Positional and keyword arguments in `args` and `kwargs`
are passed to `vtk_grid` verbatim (except file names that are augmented with the 
corresponding part id).

The extra keyword arguments only apply for parallel vtk file formats.  Mandatory ones are:

- `part` current (1-based) part id
- `nparts` total number of parts

Optional ones are
- `ismain` True if the current part id `part` is the main (the only one that will write the .pvtk file).
- `ghost_level` Ghost level.
"""
function pvtk_grid(filename::AbstractString,
                   args...;
                   part,
                   nparts,
                   ismain = (part == 1),
                   ghost_level = 0,
                   kwargs...)

  bname = basename(filename)
  mkpath(filename)
  prefix = joinpath(filename,bname)
  fn = _serial_filename(part,nparts,prefix,"")
  pvtkargs = PVTKArgs(part,nparts,ismain,ghost_level)
  xdoc  = XMLDocument()
  vtk = vtk_grid(fn,args...;kwargs...)
  _,ext = splitext(vtk.path)
  path = filename*".p"*ext[2:end]
  pvtk = PVTKFile(pvtkargs,xdoc,vtk,path)
  _init_pvtk!(pvtk)
  pvtk
end

# Add point and cell data as usual

function Base.setindex!(pvtk::PVTKFile,
                        data,
                        name::AbstractString,
                        loc::AbstractFieldData)
  pvtk.vtk[name,loc]=data
end

function Base.setindex!(pvtk::PVTKFile, data, name::AbstractString)
  pvtk.vtk[name]=data
end

# Save as usual

function vtk_save(pvtk::PVTKFile)
  if isopen(pvtk)
    if pvtk.pvtkargs.ismain
      _update_pvtk!(pvtk)
      save_file(pvtk.xdoc, pvtk.path)
    end
    vtk_save(pvtk.vtk)
    close(pvtk)
  end
  return [pvtk.path]
end

# Helper functions

function _serial_filename(part,nparts,prefix,extension)
  p = lpad(part,ceil(Int,log10(nparts)),'0')
  fn = prefix*"_$p"*extension
end

function _init_pvtk!(pvtk::PVTKFile)

  # Recover some data
  vtk = pvtk.vtk
  pvtkargs = pvtk.pvtkargs
  pgrid_type = "P"*vtk.grid_type
  npieces = pvtkargs.nparts
  pref,_ = splitext(pvtk.path)
  _,ext = splitext(vtk.path)
  prefix = joinpath(pref,basename(pref))

  # VTKFile (root) node
  pvtk_root = create_root(pvtk.xdoc, "VTKFile")
  set_attribute(pvtk_root, "type", pgrid_type)
  set_attribute(pvtk_root, "version", "1.0")
  if IS_LITTLE_ENDIAN
    set_attribute(pvtk_root, "byte_order", "LittleEndian")
  else
    set_attribute(pvtk_root, "byte_order", "BigEndian")
  end

  # Grid node
  pvtk_grid = new_child(pvtk_root,pgrid_type)
  set_attribute(pvtk_grid, "GhostLevel", string(pvtkargs.ghost_level))

  # Pieces (i.e. Pointers to serial files)
  for piece in 1:npieces
    pvtk_piece = new_child(pvtk_grid,"Piece")
    fn = _serial_filename(piece,npieces,prefix,ext)
    set_attribute(pvtk_piece,"Source",fn)
  end

  # Recover point type and number of components
  vtk_root = root(vtk.xdoc)
  vtk_grid = find_element(vtk_root,vtk.grid_type)
  vtk_piece = find_element(vtk_grid,"Piece")
  vtk_points = find_element(vtk_piece,"Points")
  vtk_data_array = find_element(vtk_points,"DataArray")
  point_type = attribute(vtk_data_array,"type")
  Nc = attribute(vtk_data_array,"NumberOfComponents")

  ## PPoints node
  pvtk_ppoints = new_child(pvtk_grid,"PPoints")
  pvtk_pdata_array = new_child(pvtk_ppoints,"PDataArray")
  set_attribute(pvtk_pdata_array,"type",point_type)
  set_attribute(pvtk_pdata_array,"Name","Points")
  set_attribute(pvtk_pdata_array,"NumberOfComponents",Nc)

  pvtk
end

function _update_pvtk!(pvtk::PVTKFile)

  vtk = pvtk.vtk
  vtk_root = root(vtk.xdoc)
  vtk_grid = find_element(vtk_root,vtk.grid_type)
  vtk_piece = find_element(vtk_grid,"Piece")

  pgrid_type = "P"*vtk.grid_type
  pvtk_root = root(pvtk.xdoc)
  pvtk_grid = find_element(pvtk_root,pgrid_type)

  # Generate PPointData
  vtk_point_data = find_element(vtk_piece,"PointData")
  if vtk_point_data !== nothing
    pvtk_ppoint_data = new_child(pvtk_grid,"PPointData")
    for vtk_data_array in child_elements(vtk_point_data)
      t = attribute(vtk_data_array,"type")
      name = attribute(vtk_data_array,"Name")
      Nc = attribute(vtk_data_array,"NumberOfComponents")
      pvtk_pdata_array = new_child(pvtk_ppoint_data,"PDataArray")
      set_attribute(pvtk_pdata_array,"type",t)
      set_attribute(pvtk_pdata_array,"Name",name)
      set_attribute(pvtk_pdata_array,"NumberOfComponents",Nc)
    end
  end

  # Generate PCellData
  vtk_cell_data = find_element(vtk_piece,"CellData")
  if vtk_cell_data !== nothing
    pvtk_pcell_data = new_child(pvtk_grid,"PCellData")
    for vtk_data_array in child_elements(vtk_cell_data)
      t = attribute(vtk_data_array,"type")
      name = attribute(vtk_data_array,"Name")
      Nc = attribute(vtk_data_array,"NumberOfComponents")
      pvtk_pdata_array = new_child(pvtk_pcell_data,"PDataArray")
      set_attribute(pvtk_pdata_array,"type",t)
      set_attribute(pvtk_pdata_array,"Name",name)
      set_attribute(pvtk_pdata_array,"NumberOfComponents",Nc)
    end
  end

  pvtk
end

