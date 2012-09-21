# 3D Model Conversion Tools
# Copyright (C) 2012   Simon Kornblith

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

type Vertex
	index::Int64
	position::Vector{Float32}
	faces::Vector{Int64}
	edges::Vector{Int64}
end
Vertex(index::Int64, position::Vector{Float32}) = Vertex(index, position, Array(Int64, 0), Array(Int64, 0))

type Edge
	index::Int64
	vertices::Vector{Int64}
	faces::Vector{Int64}
end
Edge(index::Int64, vertices::Vector{Int64}) = Edge(index, vertices, Array(Int64, 0))

type Face
	index::Int64
	edges::Vector{Int64}
	vertices::Vector{Int64}
end

# Converts an STL file to Christian Shelton's triangle mesh format
# (Used by http://www.cs.ucr.edu/~cshelton/corr/)
function stl_to_tm(input_file::String, output_file::String)
	triangles, vertices, edges, faces = stl_to_internal(input_file)

	# Write TM file
	s = open(output_file, "w")
	
	# Header
	write(s, "TMFF1\n")
	minp = squeeze(min(min(triangles, (), 3), (), 1))
	maxp = squeeze(max(max(triangles, (), 3), (), 1))
	divp = (maxp-minp)/4
	write_vector(s, [minp./divp, 0, 0, 0])
	write_vector(s, [maxp./divp, 1, 1, 1])
	write_vector(s, [divp*2, 0, 0, 0])
	write(s, "$(length(vertices)) $(length(edges)) $(length(faces))\n")

	# Vertices
	for i=1:length(vertices)
		vertex = vertices[i]
		write_vector(s, [vertex.position./divp, 0.5, 0.5, 0.5])
		write(s, "$(length(vertex.faces)) $(length(vertex.edges))\n")
		write_vector(s, vertex.faces)
		write_vector(s, vertex.edges)
	end

	# Edges
	for i=1:length(edges)
		edge = edges[i]
		write(s, "$(length(edge.faces))\n")
		write_vector(s, edge.faces)
		write_vector(s, edge.vertices)
	end

	# Faces
	for i=1:length(faces)
		face = faces[i]
		write_vector(s, face.edges)
		write_vector(s, face.vertices)
	end

	close(s)
end

# Converts an STL file to OOGL format used by VolMorph
# (http://svr-www.eng.cam.ac.uk/~gmt11/software/software.html#VolMorph)
function stl_to_off(input_file::String, output_file::String)
	triangles, vertices, edges, faces = stl_to_internal(input_file)

	s = open(output_file, "w")
	write(s, "LIST\n{\nOFF $(length(vertices)) $(length(faces)) 0\n")

	# Vertices
	for i=1:length(vertices)
		write_vector(s, vertices[i].position)
	end

	# Faces
	for i=1:length(faces)
		face_vertices = faces[i].vertices[[2, 1, 3]]
		write(s, "$(length(face_vertices))")
		for i=1:length(face_vertices)
			write(s, " $(face_vertices[i])")
		end
		write(s, "\n")
	end
	write(s, "}\n")
	close(s)
end

# Reads an STL file
function read_stl(input_file::String)
	s = open(input_file, "r")
	header = read(s, Uint8, 80)
	n_triangles = int64(read(s, Uint32))
	triangles = Array(Float32, (3, 3, n_triangles))
	normal_vectors = Array(Float32, (3, n_triangles))
	for i=1:n_triangles
		normal_vectors[:, i] = read(s, Float32, 3)
		triangles[:, :, i] = read(s, Float32, (3, 3))'
		byte_count = read(s, Uint16)
	end
	close(s)
	return normal_vectors, triangles
end

# Converts an STL file to the representation used internally
function stl_to_internal(input_file::String)
	normal_vectors, triangles = read_stl(input_file)
	n_triangles = size(triangles, 3)

	# Create data structures
	sz = n_triangles*3
	vertices_by_position = Dict{Vector{Float32}, Vertex}(sz)
	vertices_by_index = Array(Vertex, sz)
	vertex_index = 0
	edges_by_vertices = Dict{Array{Int64}, Edge}(sz)
	edges_by_index = Array(Edge, sz)
	edge_index = 0
	faces = Array(Face, 0)

	const EDGE_INDICES = [1 2; 2 3; 3 1]
	for i=1:n_triangles
		triangle_vertices = Array(Int64, 3)
		triangle_edges = Array(Int64, 3)

		face = Face(i-1, triangle_edges, triangle_vertices)
		push(faces, face)

		for j=1:3
			vertex_position = squeeze(triangles[j, :, i])
			vertex = get(vertices_by_position, vertex_position, None)
			if vertex == None
				vertex = Vertex(vertex_index, vertex_position)
				vertices_by_position[vertex_position] = vertex
				vertices_by_index[vertex_index+1] = vertex
				vertex_index += 1
			end
			push(vertex.faces, i-1)
			triangle_vertices[j] = vertex.index
		end

		for j=1:3
			edge_vertices = triangle_vertices[squeeze(EDGE_INDICES[j, :])]
			edge = get(edges_by_vertices, edge_vertices, None)
			if edge == None
				edge = get(edges_by_vertices, flipud(edge_vertices), None)
				if edge == None
					edge = Edge(edge_index, edge_vertices)
					edges_by_vertices[edge_vertices] = edge
					edges_by_index[edge_index+1] = edge
					edge_index += 1
				end
			end
			push(edge.faces, face.index)
			for k=1:2
				push(vertices_by_index[edge_vertices[k]+1].edges, edge.index)
			end
			triangle_edges[j] = edge.index
		end
	end

	return triangles, vertices_by_index[1:vertex_index], edges_by_index[1:edge_index], faces
end

# Writes a vector to an IOStream as ASCII text
function write_vector(s::IOStream, vec::Vector)
	if length(vec) != 0
		write(s, "$(vec[1])")
		for i=2:length(vec)
			write(s, " $(vec[i])")
		end
	end
	write(s, "\n")
end