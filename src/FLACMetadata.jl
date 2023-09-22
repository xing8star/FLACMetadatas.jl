include("MetadataBlock.jl")
include("BlockWrite.jl")
include("MetadataWriteBlock.jl")
export FLACMetadata,save,
add_tags!,delete_tags!
"""Convert an arbitrarily-long string to a long using big-endian
byte order."""
function to_int_be(data::Vector{UInt8})
    reduce((a, b)->((a << 8) + b),data;init=0)
end
"""Known metadata block types, indexed by ID."""
const METADATA_BLOCKS = [StreamInfo, Padding, nothing, SeekTable, VCFLACDict,
nothing, Picture]

struct FLACMetadata
    metadata_blocks::Vector{MetadataBlock}
    keys::Vector{Pair{Symbol,Int}}
    io::IO
    function FLACMetadata(io::IO)
        metadata_blocks=[]
        keys=[]
        checkheader(io,FLACMetadata)
        last_block,_size,code=read_metadata_block(io)
        id=1
        while last_block
            data = read(io,_size)
            block_type = METADATA_BLOCKS[code+1]
            block = block_type(data)
            addmetakey!(keys,block,id)
            id+=1
            push!(metadata_blocks,block)
            last_block,_size,code=read_metadata_block(io)
        end
        mark(io)
        new(metadata_blocks,keys,io)
    end
end
pretty(x::FLACMetadata)=foreach(pretty,x.metadata_blocks)
FLACMetadata(file::AbstractString)=FLACMetadata(open(file))
function checkheader(io::IO,::Type{FLACMetadata})
    @assert read(io,4)==b"fLaC" " not a valid FLAC file"
    # FLACNoHeaderError(
    true
end
function read_metadata_block(io::IO)
    byte=read(io,UInt8)
    _size=to_int_be(read(io,3))
    code=byte&0x7f
    last_block = iszero(byte & 0x80)
    last_block,_size,code
end
addmetakey!(::Vector,::MetadataBlock,::Int)=nothing
addmetakey!(x::Vector,b::MetadataBlock,blocks::Vector{MetadataBlock})=addmetakey!(x,b,length(blocks))
addmetakey!(x::Vector,::VComment,index::Int)=push!(x,:tags=>index)
addmetakey!(x::Vector,::SeekTable,index::Int)=push!(x,:seektable=>index)
addmetakey!(x::Vector,::StreamInfo,index::Int)=push!(x,:info=>index)

function Base.propertynames(x::FLACMetadata)
    fieldnames(typeof(x))...,keys(NamedTuple(x.keys))...
end
function Base.getproperty(obj::FLACMetadata,sym::Symbol)
    nt=NamedTuple(getfield(obj,:keys))
    extrasym=keys(nt)
    if sym in extrasym
        return obj.metadata_blocks[getproperty(nt,sym)]
    end
    getfield(obj,sym)
end
function Base.write(io::IO,x::FLACMetadata)
    write(io,"fLaC")
    writeblock(io,x.metadata_blocks)
end
function add_tags!(x::FLACMetadata)
    if !hasproperty(x,:tags)
        tags = VCFLACDict()
        push!(x.metadata_blocks,tags)
        addmetakey!(x.keys,tags,x.metadata_blocks)
    else
        error("a Vorbis comment already exists")
    end
end
function delete_tags!(x::FLACMetadata)
    if hasproperty(x,:tags)
        local index
        index=findfirst(x->first(x)==:tags,x.keys)
        # for (i,j) in enumerate(x.keys)
        #     if j.first==:tags
        #         index,originindex= i,j
        #         break
        #     end
        # end
        deleteat!(x.metadata_blocks,x.keys[index].second)
        deleteat!(x.keys,index)
    end
end

function save(x::FLACMetadata,file=x.io.name[7:end-1])
    f=tempname(".")
    open(f,"w+") do io
        write(io,x)
        write(io,read(x.io))
    end
    reset(x.io)
    mv(f,file, force=true)
end