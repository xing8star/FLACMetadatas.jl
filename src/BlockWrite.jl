pack(x::Integer;_length=3)=hex2bytes(lpad(string(x,base=16),_length*2,'0'))
function Base.write(io::IO,x::StreamInfo)
    write(io,ntoh(UInt16(x.min_blocksize)))
    write(io,ntoh(UInt16(x.max_blocksize)))
    write(io,pack(x.min_framesize))
    write(io,pack(x.max_framesize))
    sample_rate=x.sample_rate
    # first 16 bits of sample rate
    write(io,pack(sample_rate >> 4;_length=2))
    # 4 bits sample, 3 channel, 1 bps
    byte = (sample_rate & 0xF) << 4
    byte += ((x.channels - 1) & 7) << 1
    byte += ((x.bits_per_sample - 1) >> 4) & 1
    write(io,ntoh(UInt8(byte)))
    # 4 bits of bps, 4 of sample count
    byte = ((x.bits_per_sample - 1) & 0xF) << 4
    byte += (x.total_samples >> 32) & 0xF
    write(io,ntoh(UInt8(byte)))
    # last 32 of sample count
    write(io,ntoh(UInt32(x.total_samples & 0xFFFFFFFF)))
    # MD5 signature
    sig = x.md5_signature
    write(io,ntoh.(UInt32.(
        ((sig >> 96) & 0xFFFFFFFF, (sig >> 64) & 0xFFFFFFFF,
        (sig >> 32) & 0xFFFFFFFF, sig & 0xFFFFFFFF)
        ))...)
end
function Base.write(io::IO,x::Padding)
    write(io,repeat([0x0],x.length))
end
function Base.write(io::IO,x::SeekTable)
    for seekpoint in x.seekpoints
        write(io,
            ntoh.((UInt64(seekpoint.first_sample), UInt64(seekpoint.byte_offset),
            UInt16(seekpoint.num_samples)))...)
    end
end
Base.isequal(x::SeekTable,y::SeekTable)=x.seekpoints==y.seekpoints
Base.:(==)(x::SeekTable,y::SeekTable)=x.seekpoints==y.seekpoints
function Base.write(io::IO,x::VComment)
    vendor = codeunits(x.vendor)
    write(io,UInt32(length(vendor)))
    write(io,vendor)
    write(io,UInt32(length(x.tags)))
    for (tag, value) in pairs(x.tags)
        comment = string(tag) * '=' * value
        comment=codeunits(comment)
        write(io,UInt32(length(comment)))
        write(io,comment)
    end
    # if framing:
    #     write(b"\x01")
end

function Base.write(io::IO,x::Picture)
    mime = codeunits(x.mime)
    write(io,ntoh.(UInt32.((x.type,length(mime))))...)
    write(io,mime)
    desc = codeunits(x.desc)
    write(io,UInt32(length(desc))|>ntoh,desc)
    write(io,ntoh.(UInt32.((x.width, x.height, x.depth,
                        x.colors, length(x.data))))...)
    write(io,x.data)
end