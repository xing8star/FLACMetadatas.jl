const BLOCKCODE = Dict(StreamInfo=>0,
 Padding=>1,
  SeekTable=>3, VCFLACDict=>4,
 Picture=>6)
function writeblock(io::IO,block::MetadataBlock;is_last::Bool=false)
    blockcode=BLOCKCODE[typeof(block)]
    code = if is_last blockcode|128 else blockcode end
    write(io,UInt8(code))
    mark(io)
    write(io,zeros(UInt8,3))
    last_pos=position(io)
    write(io,block)
    _size = position(io)-last_pos
    # if size > cls._MAX_SIZE:
    #     if block._distrust_size and block._invalid_overflow_size != -1:
    #         # The original size of this block was (1) wrong and (2)
    #         # the real size doesn't allow us to save the file
    #         # according to the spec (too big for 24 bit uint). Instead
    #         # simply write back the original wrong size.. at least
    #         # we don't make the file more "broken" as it is.
    #         size = block._invalid_overflow_size
    #     else:
    #         raise error("block is too long to write")
    # assert not size > cls._MAX_SIZE
    _length = pack(_size)
    reset(io)
    write(io,_length)
    seekend(io)
end
function writeblock(io::IO,blocks::Vector{MetadataBlock})
    for block = blocks
        if block isa Padding
            continue
        end
        writeblock(io,block)
    end
    writeblock(io,Padding(4096);is_last=true)
end
