"""A generic block of FLAC metadata.

This class is extended by specific used as an ancestor for more specific
blocks, and also as a container for data blobs of unknown blocks.

"""
abstract type MetadataBlock end
pretty(::MetadataBlock)=nothing

"""StreamInfo

FLAC stream information.

This contains information about the audio data in the FLAC file.
Unlike most stream information objects in Mutagen, changes to this
one will rewritten to the file when it is saved. Unless you are
actually changing the audio stream itself, don't change any
attributes of this block.

Attributes:
    min_blocksize (`Int`): minimum audio block size
    max_blocksize (`Int`): maximum audio block size
    sample_rate (`Int`): audio sample rate in Hz
    channels (`Int`): audio channels (1 for mono, 2 for stereo)
    bits_per_sample (`Int`): bits per sample
    total_samples (`Int`): total samples in file
    length (`Float`): audio length in seconds
    bitrate (`Int`): bitrate in bits per second, as an int
"""
struct StreamInfo <:MetadataBlock
    min_blocksize::Int
    max_blocksize::Int
    min_framesize::Int
    max_framesize::Int
    sample_rate::Int32
    channels::Int8
    bits_per_sample::Int
    total_samples::UInt32
    length::Float64
    md5_signature::Int
end

function StreamInfo(data::IO)
    min_blocksize = to_int_be(read(data,2))
    max_blocksize = to_int_be(read(data,2))
    min_framesize = to_int_be(read(data,3))
    max_framesize = to_int_be(read(data,3))
    # first 16 bits of sample rate
    sample_first = to_int_be(read(data,2))
    # last 4 bits of sample rate, 3 of channels, first 1 of bits/sample
    sample_channels_bps = to_int_be(read(data,1))
    # last 4 of bits/sample, 36 of total samples
    bps_total = to_int_be(read(data,5))

    sample_tail = sample_channels_bps >> 4
    sample_rate = (sample_first << 4) + sample_tail
    # if not self.sample_rate:
    #     raise error("A sample rate value of 0 is invalid")
    channels = ((sample_channels_bps >> 1) & 7) + 1
    bps_tail = bps_total >> 36
    bps_head = (sample_channels_bps & 1) << 4
    bits_per_sample = bps_head + bps_tail + 1
    total_samples = UInt32(bps_total & 0xFFFFFFFFF)
    _length = total_samples / sample_rate
    md5_signature = to_int_be(read(data,16))
    StreamInfo(min_blocksize,max_blocksize,min_framesize,max_framesize,
    sample_rate,channels,bits_per_sample,total_samples,_length,md5_signature)
end

pretty(x::StreamInfo)=println("FLAC, $(round(x.length)) seconds, $(x.sample_rate) Hz")
"""SeekPoint

A single seek point in a FLAC file.

Placeholder seek points have first_sample of 0xFFFFFFFFFFFFFFFFL,
and byte_offset and num_samples undefined. Seek points must be
sorted in ascending order by first_sample number. Seek points must
be unique by first_sample number, except for placeholder
points. Placeholder points must occur last in the table and there
may be any number of them.

Attributes:
    first_sample (`int`): sample number of first sample in the target frame
    byte_offset (`int`): offset from first frame to target frame
    num_samples (`int`): number of samples in target frame
"""
struct SeekPoint<:MetadataBlock
    first_sample
    byte_offset
    num_samples
end
unpack(T::Type{<:Integer},x)=parse(T,bytes2hex(x),base=16)
unpack(x::Vector{UInt8})=parse(Int,bytes2hex(x),base=16)


function SeekPoint(data::Vector{UInt8})
    SeekPoint(unpack.((data[1:8],data[9:16],data[17:18]))...)
end
"""Read and write FLAC seek tables.

Attributes:
    seekpoints: list of SeekPoint objects
"""
struct SeekTable<:MetadataBlock
    seekpoints::Vector{SeekPoint}
end
Base.show(io::IO,::MIME"text/plain",x::SeekTable)=println(io,"<SeekTable seekpoints=$(x.seekpoints)>")

function SeekTable(data::IO)
    seekpoints=[]
    __SEEKPOINT_SIZE=18
    sp = read(data,__SEEKPOINT_SIZE)
    while length(sp) == __SEEKPOINT_SIZE
        push!(seekpoints,SeekPoint(sp))
        sp =  read(data,__SEEKPOINT_SIZE)
    end
    SeekTable(seekpoints)
end
"""Picture

Read and write FLAC embed pictures.

Attributes:
    type (`id3.PictureType`): picture type
        (same as types for ID3 APIC frames)
    mime (`text`): MIME type of the picture
    desc (`text`): picture's description
    width (`int`): width in pixels
    height (`int`): height in pixels
    depth (`int`): color depth in bits-per-pixel
    colors (`int`): number of colors for indexed palettes (like GIF),
        0 for non-indexed
    data (`bytes`): picture data
"""
struct Picture<:MetadataBlock
    type::Int32
    mime::String
    desc::String
    width::Int32
    height::Int32 
    depth::Int32 
    colors::Int32 
    data::Vector{UInt8}
end
# Base.show(io::IO,::MIME"text/plain",x::Picture)=println(io,"<Picture '$(x.mime)' ($(x.length) bytes)>")
pretty(x::Picture)=println("<Picture '$(x.mime)' ($(length(x.data)) bytes)>")
Picture()=Picture(0,"","",0,0,0,0,[])
function Picture(data::IO)
    type, _length = (read(data,Int32)|>ntoh for _=1:2)
    mime = read(data,_length)|>String
    # mime = readuntil(data,'\0')
    _length = read(data,Int32)|>ntoh
    # desc = readuntil(data,'\0')
    desc = read(data,_length)|>String
    width, height, depth,colors, _length = (read(data,Int32)|>ntoh for _=1:5)
    data = read(data,_length)
    Picture(type,mime,desc,width,height,depth,colors,data)
end
"""A Vorbis comment parser, accessor, and renderer.

All comment ordering is preserved. A VComment is a list of
key/value pairs, and so any Python list method can be used on it.

Vorbis comments are always wrapped in something like an Ogg Vorbis
bitstream or a FLAC metadata block, so this loads string data or a
file-like object, not a filename.

Attributes:
    vendor (text): the stream 'vendor' (i.e. writer); default 'Mutagen'
"""
struct VComment <:MetadataBlock
    vendor::String
    tags::NamedTuple
end
"""VCFLACDict()

Read and write FLAC Vorbis comments.

FLACs don't use the framing bit at the end of the comment block.
So this extends VCommentDict to not use the framing bit.
"""
const VCFLACDict=VComment
function VComment()
    VComment("FLACMetadata v0.1.0",NamedTuple())
end
VComment(data::NamedTuple)=VComment("FLACMetadata v0.1.0",data)
function VComment(data::IO)
    tags=NamedTuple()
vendor=read(data,read(data,Int32))|>String
# count =read(data,Int32)
for _ = 1:read(data,Int32)
    # _length = read(data,Int32)
    _string = read(data,read(data,Int32))|>String
    # except (OverflowError, MemoryError):
    #     raise error("cannot read %d bytes, too large" % length)
    # try:
    tag, value =split(_string ,'=';limit= 2)
    # except ValueError as err:
        # if errors == "ignore":
        #     continue
        # elif errors == "replace":
        #     tag, value = u"unknown%d" % i, string
        # else:
        #     reraise(VorbisEncodingError, err, sys.exc_info()[2])
    # try:
    #     tag = tag.encode('ascii', errors)
    # except UnicodeEncodeError:
    #     raise VorbisEncodingError("invalid tag name %r" % tag)
    # else:
    #     tag = tag.decode("ascii")
        # if is_valid_key(tag):
    # tags[tag]=value
    tags=merge(tags,(Symbol(tag)=>value,))
    # if framing &&  !(read(data1,UInt8) & 0x01)
    #     # VorbisUnsetFrameError("framing bit was unset")
    #     error("framing bit was unset")
    # end
end
VComment(vendor,tags)
end

function pretty(x::VComment)
    for (k, v) in pairs(x.tags)
        println(string(k)*"="*v)
    end
end

for i in [:StreamInfo,:SeekTable,:Picture,:VComment]
    eval(:($i(data::Vector{UInt8})=$i(IOBuffer(data))))
end
"""Padding()

Empty padding space for metadata blocks.

To avoid rewriting the entire FLAC file when editing comments,
metadata is often padded. Padding should occur at the end, and no
more than one padding block should be in any FLAC file.

Attributes:
    length (`int`): length
"""
struct Padding <:MetadataBlock
    length::Int
end
Padding(data::Vector{UInt8})=Padding(length(data))
Base.show(io::IO,::MIME"text/plain",x::Padding)=println(io,"<Padding ($(x.length) bytes)>")
# pretty(x::Union{Padding,SeekTable})=display(x)
pretty(x::Padding)=display(x)