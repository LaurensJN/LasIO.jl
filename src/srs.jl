import Base.length

struct sKeyEntry
    wKeyID::UInt16
    wTIFFTagLocation::UInt16
    wCount::UInt16
    wValue_Offset::UInt16
end

struct sGeoKeys
    wKeyDirectoryVersion::UInt16
    wKeyRevision::UInt16
    wMinorRevision::UInt16
    wNumberOfKeys::UInt16
    pKey::Vector{sKeyEntry}
end

struct GeoDoubleParamsTag
    DoubleParams::Vector{Float16}
end

struct GeoAsciiParamsTag
    AsciiParams::String
end

length(data::sGeoKeys) = 2*4*Int64(data.wNumberOfKeys)+8 #2 bytes per element
length(data::GeoDoubleParamsTag) = length(data.DoubleParams)*8
length(data::GeoAsciiParamsTag) = 256

function constructVLR(EPSG, format)
    reserved = 0xAABB
    user_id = "LASF_Projection"

    if format == "GeoTIFF"
        description = "GeoTIFF GeoKeyDirectoryTag"
        record_id = 34735
        io = IOBuffer()
        constructDirectoryTag(io,EPSG)
        seekstart(io)
        data = read(io)
        close(io)

    return LasVariableLengthRecord(
        reserved,
        user_id,
        record_id,
        description,
        data
    )
end

#Write existing VLR to bytes
function writeFromExistingVLR(io, data)
    if typeof(data) == sGeoKeys
        write(io,data.wKeyDirectoryVersion)
        write(io,data.wKeyRevision)
        write(io,data.wMinorRevision)
        write(io,data.wNumberOfKeys)
        for keyEntry in data.pKey
            writeKeyEntry(io,keyEntry)
        end
    elseif typeof(data) == GeoDoubleParamsTag
        write(io,data.DoubleParams)
    elseif typeof(data) == GeoAsciiParamsTag
        writestring(io,data.AsciiParams,256)
    else
        write(io,data) #WKT for instance
    end
end

function constructDirectoryTag(io,EPSG::Int)
    #Standard types
    is_projected = sKeyEntry(UInt16(1024), UInt16(0), UInt16(1), UInt16(1))         #Projected
    proj_linear_units = sKeyEntry(UInt16(1025), UInt16(0), UInt16(1), UInt16(1))    #Units in meter
    projected_cs_type = sKeyEntry(UInt16(3072), UInt16(0), UInt16(1), UInt16(EPSG)) #EPSG code
    vertical_units = sKeyEntry(UInt16(3076), UInt16(0), UInt16(1), UInt16(9001))    #Units in meter
    pKey = [is_projected,proj_linear_units,projected_cs_type,vertical_units]
    geokeysheader = sGeoKeys(
                UInt16(1), UInt16(1), UInt16(0), UInt16(length(pKey)),pKey)
    writeFromExistingVLR(io, geokeysheader)
end

function writeKeyEntry(io,Entry::sKeyEntry)
    write(io,Entry.wKeyID)
    write(io,Entry.wTIFFTagLocation)
    write(io,Entry.wCount)
    write(io,Entry.wValue_Offset)
end

#Set SRS code
function defineSRS(header, EPSG::Int, formats::Array{String})
    #Length existing VLR
    VLROldLength = header.n_vlr == 0 ? 0 : sum(sizeof, header.variable_length_records)
    oldOffset = header.data_offset

    #Assign VLR to header
    New_VLR = [constructVLR(EPSG,i) for i in formats]
    header.variable_length_records = New_VLR
    header.n_vlr = length(header.variable_length_records)
    VLRNewLength = header.n_vlr == 0 ? 0 : sum(sizeof, header.variable_length_records)

    #Update offset to point data
    header.data_offset = oldOffset - VLROldLength + VLRNewLength
    write(IOBuffer(),header)
end

function deconstructVLRData(io, record_id, length::Int=0)
    if record_id == 34735
        wKeyDirectoryVersion = read(io,UInt16)
        wKeyRevision = read(io,UInt16)
        wMinorRevision = read(io,UInt16)
        wNumberOfKeys = read(io,UInt16)
        pKey = sKeyEntry[]
        for i in 1:Int(wNumberOfKeys)
            wKeyID = read(io,UInt16)
            wTIFFTagLocation = read(io,UInt16)
            wCount = read(io,UInt16)
            wValue_Offset = read(io,UInt16)

            push!(pKey, sKeyEntry(
                wKeyID,
                wTIFFTagLocation,
                wCount,
                wValue_Offset
            ))
        end
        return sGeoKeys(
            wKeyDirectoryVersion,
            wKeyRevision,
            wMinorRevision,
            wNumberOfKeys,
            pKey
        )

    elseif record_id == 34736
        DoubleParams = reinterpret(Float64,read(io,length))
        return GeoDoubleParamsTag(
            DoubleParams
        )

    elseif record_id == 34737
        AsciiParams = readstring(io,length)
        return GeoAsciiParamsTag(
            AsciiParams,
        )
    end
end
