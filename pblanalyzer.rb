require 'cstruct'

class Header_Block < CStruct
  char :hdr, [4]  # HDR*
  char :name, [14]  # 'PowerBuilder' + 0x00 + 0x00
  char :version, [4]  # PBL Format Version? (0400/0500/0600)
  int32 :modified_date
  char :reserved0, [2]
  char :comment, [256]
  int32 :first_scc_data_offset
  int32 :scc_data_size # net size of SCC data
  char :reserved1, [220]
end

class Bitmap_Block < CStruct
  char :fre, [4]  # FRE*
  int32 :next_block_offset  # offset of next block or 0
  char :bitmap, [504]  # each bit represents a block
end

class Node_Block < CStruct
  char :nod, [4]  # NOD*
  int32 :prev_block_offset  # offset of previous (left) block or 0
  int32 :parent_block_offset  # offset of parent block or 0
  int32 :next_block_offset  # offset of next (right) block or 0
  int16 :space_left_in_block  # initial = 3040
  int16 :first_objectname_position
  int16 :entries_count
  int16 :last_objectname_position
  char :reserved0, [8]
  char :entry_chunks, [3040]
end

class Entry_Chunk < CStruct
  char :ent, [4]  # ENT*
  char :version, [4]  # PBL version? (0400/0500/0600)
  int32 :first_data_block_offset
  int32 :object_size  # Net size of data
  int32 :modified_date
  int16 :comment_length
  int16 :object_name_length
end

class Data_Block < CStruct
  char :dat, [4]  # 'DAT*'
  int32 :next_data_block_offset
  int16 :block_data_length
  char :blob, [502]
end

# [{name: 'example.sra', offset: 0x00001000}, {name: 'example.pra', offset: 0x00001400}]
@object_list = []

def int_array_to_str(array)
  array.pack("C#{array.size}")
end

def int_to_hex_str(value)
  '0X' + value.to_s(16).upcase.rjust(8, '0')
end

def read_header_block(sdata)
  header = Header_Block.new
  header << sdata

  puts '### Library Header Block (512 Byte)'
  puts int_array_to_str(header.hdr)
  puts int_array_to_str(header.name).strip
  puts int_array_to_str(header.version)
  puts Time.at(header.modified_date)
  puts int_to_hex_str(header.first_scc_data_offset) + '  <- Offset of first SCC data block'
  puts int_to_hex_str(header.scc_data_size) + '  <- Size (Net size of SCC data)'
end

def read_bitmap_block(sdata)
  bitmap = Bitmap_Block.new
  bitmap << sdata

  puts '### Bitmap Block (512 Byte)'
  puts int_array_to_str(bitmap.fre)
  puts int_to_hex_str(bitmap.next_block_offset) + '  <- Offset of next block or 0'
end

def read_node_block(sdata)
  node = Node_Block.new
  node << sdata

  puts '### Node Block (3072 Byte)'
  puts int_array_to_str(node.nod)
  puts int_to_hex_str(node.prev_block_offset) + '  <- Offset of next (left) block or 0'
  puts int_to_hex_str(node.parent_block_offset) + '  <- Offset of parent block or 0'
  puts int_to_hex_str(node.next_block_offset) + '  <- Offset of next (right) block or 0'
  puts int_to_hex_str(node.space_left_in_block) + '  <- Space left in block, initial = 3040'
  puts int_to_hex_str(node.first_objectname_position) + '  <- Position of alphabetically first Objectname in this block'
  puts int_to_hex_str(node.entries_count) + '  <- Count of entries in that node'
  puts int_to_hex_str(node.last_objectname_position) + '  <- Position of alphabetically last Objectname in this block'

  return [int_array_to_str(node.entry_chunks), node.entries_count]
end

def read_entry_chunk(sdata, i)
  entry = Entry_Chunk.new
  entry << sdata

  puts '### ' + i.to_s + ' Entry Chunk (Variable Length)'
  puts int_array_to_str(entry.ent)
  puts int_array_to_str(entry.version)
  puts Time.at(entry.modified_date)
  puts int_to_hex_str(entry.first_data_block_offset) + '  <- Offset of first data block'
  puts int_to_hex_str(entry.object_size) + '  <- Objectsize (Net size of data)'
  puts int_to_hex_str(entry.comment_length) + '  <- Length of Comment'
  puts int_to_hex_str(entry.object_name_length) + '  <- Length of Objectname'

  return [entry.object_name_length, entry.first_data_block_offset]
end

def read_entry_chunks(sdata, count)
  offset = 0
  count.times do |i|
    object_name_length, first_data_block_offset = read_entry_chunk(sdata.slice(offset, Entry_Chunk.size), i)

    # output object name
    offset += Entry_Chunk.size
    object_name = sdata.slice(offset, object_name_length).strip!
    puts object_name + '  <- Objectname'

    offset += object_name_length

    @object_list << {name: object_name, offset: first_data_block_offset}
  end
end

def read_data_block(sdata)
  data = Data_Block.new
  data << sdata

  #puts '### Data Block (512 Byte)'
  #puts int_array_to_str(data.dat)
  #puts int_to_hex_str(data.next_data_block_offset) + '  <- Offset of next data block or 0'
  #puts int_to_hex_str(data.block_data_length) + '  <- Length of data in block'

  data_blob = int_array_to_str(data.blob)
  if data.next_data_block_offset == 0
    puts data_blob.rstrip
  else
    print data_blob
  end

  return data.next_data_block_offset
end

pbl_file = ARGV[0]
pbl_file_path = Dir.pwd + '/' + pbl_file

sdata = File.open(pbl_file_path, 'rb').readlines.join

offset = 0
length = Header_Block.size
read_header_block(sdata.slice(offset, length))

offset += length
length = Bitmap_Block.size
read_bitmap_block(sdata.slice(offset, length))

offset += length
length = Node_Block.size
entry_chunks, entries_count = read_node_block(sdata.slice(offset, length))
read_entry_chunks(entry_chunks, entries_count)

@object_list.each do |object|
  object_name = object[:name]
  if object_name.end_with?('.apl') || object_name.end_with?('.pra') ||
     object_name.end_with?('.dwo') || object_name.end_with?('.fun') ||
     object_name.end_with?('.men') || object_name.end_with?('.str') ||
     object_name.end_with?('.str') || object_name.end_with?('.udo') ||
     object_name.end_with?('.win')
    next
  end
  puts '#### BEGIN ' + object_name
  data_block_offset = object[:offset]
  while data_block_offset != 0
    data_block_offset = read_data_block(sdata.slice(data_block_offset, Data_Block.size))
  end
  puts '#### END ' + object_name
end
