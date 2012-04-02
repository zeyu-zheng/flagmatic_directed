"""

flagmatic 2

Copyright (c) 2012, E. R. Vaughan. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1) Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.

2) Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

"""

#clang c

#
# TODO: enforce number of vertices <= 7.
#  More sanity checking.
#
#
#

include "interrupt.pxi"
include "stdsage.pxi"
include "cdefs.pxi"


from libc.stdlib cimport malloc, calloc, realloc, free
from libc.string cimport memset

import numpy
cimport numpy

from copy import copy

from sage.structure.sage_object import SageObject       
from sage.structure.sage_object cimport SageObject

from sage.rings.arith import binomial, falling_factorial
from sage.combinat.all import Combinations, Permutations, Tuples
from sage.rings.all import Integer, QQ
from sage.matrix.all import matrix
from sage.graphs.all import Graph, DiGraph

# 35 + 42 + 7 = 84, 84 * 3 = 252
DEF MAX_NUMBER_OF_EDGE_INTS = 256

# TODO: check that flag contains type

cdef class Flag (SageObject):

	cdef int _n
	cdef int _r
	cdef bint _oriented
	cdef int _t
	cdef readonly bint is_degenerate
	cdef readonly int ne
	cdef int _edges[MAX_NUMBER_OF_EDGE_INTS]
	cdef public Flag type


	def __init__(self, string_rep=None, r=3, oriented=False):
	
		if oriented and r != 2:
			raise NotImplementedError("only 2-graphs can be oriented.")
	
		self._r = r
		self._oriented = oriented
	
		if string_rep:
			self.init_from_string(string_rep)


	property edges:
		"""
		A tuple containing the edges as tuples.
		"""

		def __get__(self):
	
			cdef int i
			edge_list = []
			if self._r == 3:
				for i in range(0, 3 * self.ne, 3):
					edge_list.append((self._edges[i], self._edges[i + 1], self._edges[i + 2]))
			elif self._r == 2:
				for i in range(0, 2 * self.ne, 2):
					edge_list.append((self._edges[i], self._edges[i + 1]))
				
			return tuple(edge_list)


	property r:
		"""
		The number of vertices in an edge.
		"""

		def __get__(self):
			return self._r
	
		def __set__(self, value):

			if not (value == 2 or value == 3):
				raise NotImplementedError("only 2-graphs and 3-graphs are supported.")
				
			if self.ne != 0:
				raise ValueError

			self._r = value


	property oriented:
		"""
		Whether the order of vertices within an edge is significant.
		"""

		def __get__(self):
			return self._oriented
	
		def __set__(self, value):

			if not (value is True or value is False):
				raise ValueError
			
			self._oriented = value


	property n:
		"""
		The number of vertices.
		"""

		def __get__(self):
			return self._n
	
		def __set__(self, value):

			if value < self._n:
				raise ValueError

			self._n = value


	property t:
		"""
		The number of labelled vertices.
		"""

		def __get__(self):
			return self._t
	
		def __set__(self, value):

			if value > self._n:
				raise ValueError

			self._t = value

	def Graph(self):
		"""
		Returns a Sage Graph or DiGraph object. Does not work for 3-graphs.
		"""
					
		if self._r != 2:
			raise("NotImplementedError")
		
		if self._oriented:
			return DiGraph([e for e in self.edges])
		else:
			return Graph([e for e in self.edges])


	def add_edge(self, edge):
	
		cdef int x, y, z
		
		if self._r == 3:

			if (self.ne + 1) * 3 > MAX_NUMBER_OF_EDGE_INTS:
				raise NotImplementedError("Too many edges.")
		
			x = <int?> edge[0]
			y = <int?> edge[1]
			z = <int?> edge[2]
			if x < 1 or y < 1 or z < 1:
				raise ValueError
			if x > self._n or y > self._n or z > self._n:
				raise ValueError
	
			self._edges[3 * self.ne] = x
			self._edges[3 * self.ne + 1] = y
			self._edges[3 * self.ne + 2] = z
			self.ne += 1
	
			if x == y or x == z or y == z:
				self.is_degenerate = True

		elif self._r == 2:

			if (self.ne + 1) * 2 > MAX_NUMBER_OF_EDGE_INTS:
				raise NotImplementedError("Too many edges.")
		
			x = <int?> edge[0]
			y = <int?> edge[1]
			if x < 1 or y < 1:
				raise ValueError
			if x > self._n or y > self._n:
				raise ValueError
	
			self._edges[2 * self.ne] = x
			self._edges[2 * self.ne + 1] = y
			self.ne += 1
	
			if x == y:
				self.is_degenerate = True
		

	def __getitem__(self, name):
	
		cdef int i = <int?> name
		if i < self.ne:
			if self._r == 3:
				return (self._edges[3 * i], self._edges[3 * i + 1], self._edges[3 * i + 2])
			elif self._r == 2:
				return (self._edges[2 * i], self._edges[2 * i + 1])			
		else:
			raise IndexError


	def __iter__(self):
	
		return list(self.edges).__iter__()
	
	
	# TODO: handle > 16 vertices. 
	
	def init_from_string(self, s):

		cdef int i, t, n, ne, x

		if s[1] != ":":
			print s
			raise ValueError

		n = int(s[0], 16) # read in hex
		if n < 0:
			raise ValueError
		self._n = n
		self.ne = 0

		if s[-1] == ")":
			if s[-3] != "(":
				raise ValueError
			t = int(s[-2], 16)
			if t > n:
				raise ValueError
			s = s[:-3]
		else:
			t = 0
		self._t = t

		ne = len(s) - 2
		
		if ne > MAX_NUMBER_OF_EDGE_INTS:
			raise NotImplementedError("Too many edges.")
		
		if self._r == 3:
		
			if ne % 3 != 0:
				raise ValueError
			ne /= 3
				
			for i in range(ne):	 # N.B. +2 because of n: header
				self.add_edge((int(s[i * 3 + 2], 16), int(s[i * 3 + 3], 16), int(s[i * 3 + 4], 16)))

		elif self._r == 2:
		
			if ne % 2 != 0:
				raise ValueError
			ne /= 2
				
			for i in range(ne):	 # N.B. +2 because of n: header
				self.add_edge((int(s[i * 2 + 2], 16), int(s[i * 2 + 3], 16)))
	

	# TODO: handle > 15 vertices properly
	# Note that hex(4) gives '0x4', and so hex(4)[-1] gives '4'.

	def _repr_(self):

		cdef int i
		string_rep = hex(self._n)[-1] + ":"
		for i in range(self._r * self.ne):
			string_rep += hex(self._edges[i])[-1]
		if self._t > 0:
			string_rep += "(" + hex(self._t)[-1] + ")"
		return string_rep
 	
	def _latex_(self):
		return "\\verb|" + self._repr_() + "|"
 	
	def __cmp__(self, other):
		return self.is_equal(other)
 	
	def __reduce__(self):
		return (Flag, (self._repr_(), self._r, self._oriented))


	# TODO: work out how to make sets of these work
	
	def __hash__(self):
		return hash(self._repr_() + str(self._r) + str(self._oriented))

 	

	# TODO: do this the Cythonic way (__richcmp__ ?)
	
	def is_equal(self, Flag other):
	
		cdef int i

		if self._r != other._r:
			return False

		if self._oriented != other._oriented:
			return False

		if self._n != other._n:
			return False

		if self._t != other._t:
			return False

		if self.ne != other.ne:
			return False

		for i in range(self._r * self.ne):
			if self._edges[i] != other._edges[i]:
				return False
	
		return True

	

	# TODO: maintain vigilance that we have everything...

	def copy(self):
	
		cdef int i
		ng = Flag()
		ng.n = self._n
		ng.r = self._r
		ng.oriented = self._oriented
		ng.t = self._t
		ng.ne = self.ne
		ng.is_degenerate = self.is_degenerate

		for i in range(self._r * self.ne):
			ng._edges[i] = self._edges[i]
		
		return ng


	# TODO: possibly something different with degenerate graphs?

	def degrees(self):
		"""
		Returns a list of vertex degrees. Orientation not taken into account.
		"""
		cdef int i
		deg_list = [0 for i in range(self._n)]
		for i in range(self._r * self.ne):
			deg_list[self._edges[i] - 1] += 1
		return tuple(deg_list)


	# TODO: possibly something different with degenerate graphs?
	
	def edge_density(self):
		"""
		Returns the edge density, i.e. the number of edges divided by binomial(n, 3),
		where n is the number of vertices.
		"""
		if self.is_degenerate:
			raise NotImplementedError("degenerate graphs are not supported.")
		
		return self.ne / binomial(self.n, self.r)


	def subgraph_density(self, h):
		"""
		Returns the H-density. That is, the number of k-sets of vertices that induce
		graphs isomorphic to H, divided by binomial(n, k). Ignores vertex labels.
		"""
		
		if self.is_degenerate:
			raise NotImplementedError("degenerate graphs are not supported.")
		
		# Short-cut if we are dealing with edge/non-edge density
		if h.n == self.r:
			if h.ne == 1:
				return self.edge_density()
			else:
				return 1 - self.edge_density()
		
		found, total = 0, 0
		minh = h.copy()
		minh.t = 0
		minh.make_minimal_isomorph()
		
		for hv in Combinations(range(1, self.n + 1), h.n):
			ig = self.induced_subgraph(hv)
			ig.make_minimal_isomorph()
			if minh.is_equal(ig):
				found += 1
			total += 1
	
		return Integer(found) / total


	def relabel(self, verts):

		cdef int i
	
		if len(verts) != self._n:
			raise ValueError
	
		for i in range(len(verts)):
			if verts[i] < 1 or verts[i] > self._n:
				raise ValueError
	
		for i in range(self._r * self.ne):
			self._edges[i] = verts[self._edges[i] - 1]

		self.minimize_edges()

	
	def minimize_edges(self):
	
		raw_minimize_edges(self._edges, self.ne, self._r, self._oriented)


	def make_minimal_isomorph(self):

		cdef int i, *new_edges, *winning_edges, *e
		cdef int *p, np, is_lower
		
		new_edges = <int *> malloc (sizeof(int) * self._r * self.ne)
		winning_edges = <int *> malloc (sizeof(int) * self._r * self.ne)
		
		p = generate_permutations_fixing(self._n, self._t, &np)
	
		for i in range(np):
		
			for j in range(self._r * self.ne):
				new_edges[j] = p[self._n * i + self._edges[j] - 1]
		
			raw_minimize_edges(new_edges, self.ne, self._r, self._oriented)
	
			if i == 0:
				for j in range(self._r * self.ne):
					winning_edges[j] = new_edges[j]
				continue
	
			is_lower = 1
	
			for j in range(self._r * self.ne):
				if new_edges[j] > winning_edges[j]:
					is_lower = 0
					break
				elif new_edges[j] < winning_edges[j]:
					break
			
			if is_lower: # We have a new winner
				for j in range(self._r * self.ne):
					winning_edges[j] = new_edges[j]
		
		for i in range(self._r * self.ne):
			self._edges[i] = winning_edges[i]
		
		free(new_edges)
		free(winning_edges)


	def induced_subgraph(self, verts):
		"""
		Returns subgraphs induced by verts. Returned Flag is always unlabelled.
		"""
	
		if self.is_degenerate:
			raise NotImplementedError("degenerate graphs are not supported.")
	
		cdef int i, *c_verts, num_verts
		cdef Flag ig
		
		num_verts = len(verts)
		c_verts = <int *> malloc(num_verts * sizeof(int))
		
		for i in range(num_verts):
			c_verts[i] = <int ?> verts[i]
		
		ig = self.c_induced_subgraph(c_verts, num_verts)
		return ig


	cdef Flag c_induced_subgraph(self, int *verts, int num_verts):

		cdef int nm = 0, i, j, *e, got, te[3]
		cdef Flag ig = Flag()

		if self.is_degenerate:
			raise NotImplementedError("degenerate graphs are not supported.")

		ig.n = num_verts
		ig.r = self._r
		ig.oriented = self._oriented
		ig.t = 0

		if self._r == 3:
		
			for i in range(self.ne):
				e = &self._edges[3 * i]
				got = 0
				for j in range(num_verts):
					if e[0] == verts[j]:
						got += 1
						te[0] = j + 1
					elif e[1] == verts[j]:
						got += 1
						te[1] = j + 1
					elif e[2] == verts[j]:
						got += 1
						te[2] = j + 1
				if got == 3:
					e = &ig._edges[3 * nm]
					e[0] = te[0]
					e[1] = te[1]
					e[2] = te[2]
					nm += 1

		elif self._r == 2:

			for i in range(self.ne):
				e = &self._edges[2 * i]
				got = 0
				for j in range(num_verts):
					if e[0] == verts[j]:
						got += 1
						te[0] = j + 1
					elif e[1] == verts[j]:
						got += 1
						te[1] = j + 1
				if got == 2:
					e = &ig._edges[2 * nm]
					e[0] = te[0]
					e[1] = te[1]
					nm += 1

		ig.ne = nm
		ig.minimize_edges()
		return ig
	

	cdef int c_has_subgraph (self, Flag h):
		"""
		Determines if it contains h as a subgraph. Labels are ignored.
		"""
	
		cdef int i, j, k, l, *p, np, *new_edges, got_all, got_edge, got
	
		if self.is_degenerate:
			raise NotImplementedError("degenerate graphs are not supported.")

		if self._r != h._r or self._oriented != h._oriented:
			raise ValueError
			
		new_edges = <int *> malloc (sizeof(int) * self._r * self.ne)
		
		p = generate_permutations(self._n, &np)
	
		for i in range(np):
		
			for j in range(self._r * self.ne):
				new_edges[j] = p[self._n * i + self._edges[j] - 1]
				
			got_all = 1
			for j in range(h.ne):
				got_edge = 0
				
				if self._r == 3:
					for k in range(self.ne):
						got = 0
						for l in range(3):
							if (h._edges[3 * j] == new_edges[(3 * k) + l] or 
								h._edges[(3 * j) + 1] == new_edges[(3 * k) + l] or
								h._edges[(3 * j) + 2] == new_edges[(3 * k) + l]):
								got += 1
						if got == 3:
							got_edge = 1
							break
					if got_edge == 0:
						got_all = 0
						break
				
				elif self._r == 2:
					for k in range(self.ne):
						if (h._edges[2 * j] == new_edges[2 * k]
							and h._edges[2 * j + 1] == new_edges[2 * k + 1]):
							got_edge = 1
						elif not self._oriented and (h._edges[2 * j] == new_edges[2 * k + 1]
							and h._edges[2 * j + 1] == new_edges[2 * k]):
							got_edge = 1
					if got_edge == 0:
						got_all = 0
						break						
			
			if got_all:
				free(new_edges)
				return 1
	
		free(new_edges)
		return 0


	# TODO: ValueError on invalid forbidden_edge_numbers (currently they are ignored)
	
	def has_forbidden_edge_numbers(self, forbidden_edge_numbers, must_have_highest=False):
	
		cdef int *c, nc, i, j, k, l, fe, *edges, *e, got, *comb, num_e, max_e, ceiling
	
		if self.is_degenerate:
			raise NotImplementedError("degenerate graphs are not supported.")

		forb_k = [pair[0] for pair in forbidden_edge_numbers]
	
		for k in range(self._r, self._n + 1): # only conditions in this range make sense

			if not k in forb_k:
				continue
			
			if self._r == 3:
				max_e = k * (k - 1) * (k - 2) / 6
			else:
				max_e = k * (k - 1) / 2
			
			forbidden_edge_nums = <int *> calloc(max_e + 1, sizeof(int))

			for i in range(max_e + 1):
				if (k, i) in forbidden_edge_numbers:
					forbidden_edge_nums[i] = 1
			
			ceiling = max_e + 1
			for i in range(max_e, -1, -1):
				if forbidden_edge_nums[i] == 1:
					ceiling = i
				else:
					break
			
			if must_have_highest:
			
				c = generate_combinations(self._n - 1, k - 1, &nc)
	
				for i in range(nc):
					comb = &c[(k - 1) * i]
					num_e = 0
					for j in range(self.ne):
						got = 0
						if self._r == 3:
							e = &self._edges[3 * j]
							for l in range(k - 1):
								if comb[l] == e[0] or comb[l] == e[1] or comb[l] == e[2]:
									got += 1
							if self._n == e[0] or self._n == e[1] or self._n == e[2]:
									got += 1
							if got == 3:
								num_e += 1
								if num_e == ceiling:
									return True
						elif self._r == 2:
							e = &self._edges[2 * j]
							for l in range(k - 1):
								if comb[l] == e[0] or comb[l] == e[1]:
									got += 1
							if self._n == e[0] or self._n == e[1]:
									got += 1
							if got == 2:
								num_e += 1
								if num_e == ceiling:
									return True
					if forbidden_edge_nums[num_e] == 1:
						return True
	
			else:
	
				c = generate_combinations(self._n, k, &nc)
	
				for i in range(nc):
					comb = &c[k * i]
					num_e = 0
					for j in range(self.ne):
						got = 0
						if self._r == 3:
							e = &self._edges[3 * j]
							for l in range(k):
								if comb[l] == e[0] or comb[l] == e[1] or comb[l] == e[2]:
									got += 1
							if got == 3:
								num_e += 1
								if num_e == ceiling:
									return True
						elif self._r == 2:
							e = &self._edges[2 * j]
							for l in range(k):
								if comb[l] == e[0] or comb[l] == e[1]:
									got += 1
							if got == 2:
								num_e += 1
								if num_e == ceiling:
									return True
					if forbidden_edge_nums[num_e] == 1:
						return True
	
		return False


	def has_forbidden_graphs(self, graphs, must_have_highest=False, induced=False):
	
		cdef int *c, nc, i, j, k, cne, *cur_edges, *e
		cdef Flag h, ig
		
		if self.is_degenerate:
			raise NotImplementedError("degenerate graphs are not supported.")
		
		cur_edges = <int *> malloc (sizeof(int) * self._r * self.ne)
		
		for i in range(len(graphs)):
	
			h = <Flag ?> graphs[i]
	
			if h._n > self._n:
				continue # vacuous condition
	
			if must_have_highest:
				c = generate_combinations_plus(self._n, h._n, &nc)
			else:
				c = generate_combinations(self._n, h._n, &nc)
	
			for j in range(nc):
			
				ig = self.c_induced_subgraph(&c[j * h._n], h._n)
			
				if ig.ne < h.ne:
					continue
					
				if induced and ig.ne > h.ne:
					continue
				
				if ig.c_has_subgraph(h):
					free(cur_edges)
					return True
	
		free(cur_edges)
		return False


	def split_vertex (self, x):
		"""
		Returns the graph obtained by cloning vertex x. Especially useful for
		degenerate graphs. 
		"""

		if self._oriented and self.is_degenerate:
			raise NotImplementedError

		if x < 1 or x > self._n:
			raise ValueError
	
		ng = self.copy()
		ng.n += 1
		nv = self._n + 1
		
		if self._r == 3:
		
			for e in self.edges:
			
				le = list(e)
				if le.count(x) == 1:
					nle = [y for y in le if y != x]
					ng.add_edge(nle + [nv])
				elif le.count(x) == 2:
					nle = [y for y in le if y != x]
					ng.add_edge(nle + [x, nv])
					ng.add_edge(nle + [nv, nv])
				elif le.count(x) == 3:
					ng.add_edge((x, x, nv))
					ng.add_edge((x, nv, nv))
					ng.add_edge((nv, nv, nv))

		elif self._r == 2:
		
			for e in self.edges:
				if e[0] == x:
					if e[1] == x:
						ng.add_edge((x, nv))
						ng.add_edge((nv, nv))
					else:
						ng.add_edge((nv, e[1]))
				elif e[1] == x:
					ng.add_edge((e[0], nv))

		return ng


	def degenerate_induced_subgraph(self, verts):

		if self._oriented and self.is_degenerate:
			raise NotImplementedError
		
		cg = self.copy()
		vertices = []
		for x in verts:
			if not x in vertices:
				vertices.append(x)
			else:
				cg = cg.split_vertex(x)
				vertices.append(cg.n)
		
		ng = Flag()
		ng.n = len(vertices)
		ng.r = self._r
		ng.oriented = self._oriented
		ng.t = 0
		
		if self._r == 3:
			for e in cg.edges:
				if e[0] in vertices and e[1] in vertices and e[2] in vertices:
					x = vertices.index(e[0]) + 1
					y = vertices.index(e[1]) + 1
					z = vertices.index(e[2]) + 1
					if x != y and x != z and y != z:
						ng.add_edge((x, y, z))

		elif self._r == 2:
			for e in cg.edges:
				if e[0] in vertices and e[1] in vertices:
					x = vertices.index(e[0]) + 1
					y = vertices.index(e[1]) + 1
					if x != y:
						ng.add_edge((x, y))

		ng.minimize_edges()
		return ng


	def degenerate_edge_density(self):

		if self._oriented:
			raise NotImplementedError
		
		if self._r == 3:
			return self.degenerate_subgraph_density(Flag("3:123"))
		elif self._r == 2:
			return self.degenerate_subgraph_density(Flag("2:12", 2))
		

	def degenerate_subgraph_density(self, h):
		"""
		Returns the H-density. That is, the number of k-sets of vertices that induce
		graphs isomorphic to H, divided by binomial(n, k).
		"""

		if self.oriented and self.is_degenerate:
			raise NotImplementedError

		if h.is_degenerate:
			raise NotImplementedError
			
		if self.r != h.r:
			raise NotImplementedError
				
		found, total = 0, 0
		minh = h.copy()
		minh.t = 0
		minh.make_minimal_isomorph()
		
		for hv in Tuples(range(1, self.n + 1), h.n):
			ig = self.degenerate_induced_subgraph(hv)
			ig.make_minimal_isomorph()
			if minh.is_equal(ig):
				found += 1
			total += 1
	
		return Integer(found) / total
		
	
	def degenerate_flag_density(self, tg, flags, type_verts):
		"""
		Note that flags must be minimal isomorphs. tg must not contain any labelled vertices.
		"""
		if tg.t != 0:
			raise NotImplementedError("type should not contain labelled vertices.")
		
		s = tg.n
		m = flags[0].n   # TODO: Check all flags are the same size, and are minimal isomorphs

		count = [0 for i in range(len(flags))]
		total = 0

		it = self.degenerate_induced_subgraph(type_verts)
		if not tg.is_equal(it):
			return count
	
		# TODO: Work out why UnorderedTuple is slower!
		
# 		for pf in UnorderedTuples(range(1, self._n + 1), m - s):
 			
# 			factor = factorial(m - s)
# 			for i in range(1, self._n + 1):
# 				factor /= factorial(pf.count(i))
	
		for pf in Tuples(range(1, self.n + 1), m - s):
			factor = 1
			
			p = list(type_verts) + pf			
			ig = self.degenerate_induced_subgraph(p)
			ig.t = s
			ig.make_minimal_isomorph()
			for i in range(len(flags)):
				if ig.is_equal(flags[i]):
					count[i] += factor
					break

			total += factor
		
		return [Integer(count[i]) / total for i in range(len(flags))]


cdef void raw_minimize_edges(int *edges, int m, int r, bint oriented):

	cdef int i, *e, round, swapped
	
	if r == 3:

		for i in range(m):
			e = &edges[i * 3]
			if e[0] > e[1]:
				e[0], e[1] = e[1], e[0]
			if e[1] > e[2]:
				e[1], e[2] = e[2], e[1]
			if e[0] > e[1]:
				e[0], e[1] = e[1], e[0]
	
		round = 1
		
		while True:
		
			swapped = 0
			for i in range(m - round):
				
				e = &edges[i * 3]
				
				if e[0] < e[3]:
					continue
				if e[0] == e[3]:
					if e[1] < e[4]:
						continue
					if e[1] == e[4]:
						if e[2] < e[5]:
							continue
							
				e[0], e[3] = e[3], e[0]
				e[1], e[4] = e[4], e[1]
				e[2], e[5] = e[5], e[2]
	
				swapped = 1
				
			if swapped == 0:
				break
				
			round += 1

	elif r == 2:
	
		if oriented == False:
		
			for i in range(m):
				e = &edges[i * 2]
				if e[0] > e[1]:
					e[0], e[1] = e[1], e[0]
		
		round = 1
		
		while True:
		
			swapped = 0
			for i in range(m - round):
				
				e = &edges[i * 2]
				
				if e[0] < e[2]:
					continue
				if e[0] == e[2]:
					if e[1] < e[3]:
						continue
							
				e[0], e[2] = e[2], e[0]
				e[1], e[3] = e[3], e[1]
	
				swapped = 1
				
			if swapped == 0:
				break
				
			round += 1


cdef class combinatorial_info_block:
	cdef int np
	cdef int *p


previous_permutations = {}

cdef int *generate_permutations_fixing(int n, int s, int *number_of):

	cdef int *p, fac, i, j

	# see if we've already generated it!
	key = (n, s)
	if key in previous_permutations.iterkeys():
	
		cib = <combinatorial_info_block>previous_permutations[key]
		fac = cib.np
		p = cib.p
	
	else:

		perms = Permutations(range(s + 1, n + 1)).list()
		fac = len(perms)
		p = <int *> malloc (sizeof(int) * n * fac)
		for i in range(fac):
			for j in range(n):
				if j < s:
					p[(i * n) + j] = j + 1
				else:
					p[(i * n) + j] = <int> perms[i][j - s]

		cib = combinatorial_info_block()
		cib.np = fac
		cib.p = p
		previous_permutations[key] = cib
	
	if number_of:
		number_of[0] = fac

	return p

cdef int *generate_permutations(int n, int *number_of):

	return generate_permutations_fixing(n, <int> 0, number_of)

def get_permutations (n):
 
	cdef int *p, np, i, j
	p = generate_permutations(n, &np)
	return [[p[(i * n) + j] for j in range(n)] for i in range(np)]


previous_combinations = {}

cdef int *generate_combinations(int n, int s, int *number_of):

	cdef int *p, fac, i, j

	# see if we've already generated it!
	key = (n, s)
	if key in previous_combinations.iterkeys():
	
		cib = <combinatorial_info_block>previous_combinations[key]
		fac = cib.np
		p = cib.p

	else:

		perms = Combinations(range(1, n + 1), s).list()
		fac = len(perms)
		p = <int *> malloc (sizeof(int) * s * fac)
		for i in range(fac):
			for j in range(s):
				p[(i * s) + j] = <int> perms[i][j]

		cib = combinatorial_info_block()
		cib.np = fac
		cib.p = p
		previous_combinations[key] = cib
	
	if number_of:
		number_of[0] = fac

	return p

def get_combinations (n, s):

	cdef int *p, np, i, j
	p = generate_combinations(n, s, &np)
	return [[p[(i * s) + j] for j in range(s)] for i in range(np)]


# Combinations that always contain maximum element
previous_combinations_plus = {}

cdef int *generate_combinations_plus(int n, int s, int *number_of):

	cdef int *p, fac, i, j

	# see if we've already generated it!
	key = (n, s)
	if key in previous_combinations_plus.iterkeys():
	
		cib = <combinatorial_info_block>previous_combinations_plus[key]
		fac = cib.np
		p = cib.p

	else:

		perms = Combinations(range(1, n), s - 1).list()
		fac = len(perms)
		p = <int *> malloc (sizeof(int) * s * fac)
		for i in range(fac):
			for j in range(s - 1):
				p[(i * s) + j] = <int> perms[i][j]
			p[(i * s) + s - 1] = n

		cib = combinatorial_info_block()
		cib.np = fac
		cib.p = p
		previous_combinations_plus[key] = cib
	
	if number_of:
		number_of[0] = fac

	return p


def get_combinations_plus (n, s):

	cdef int *p, np, i, j
	p = generate_combinations_plus(n, s, &np)
	return [[p[(i * s) + j] for j in range(s)] for i in range(np)]


previous_pair_combinations = {}

cdef int *generate_pair_combinations(int n, int s, int m1, int m2, int *number_of):

	cdef int *p, fac, i, j

	# see if we've already generated it!
	key = (n, s, m1, m2)
	if key in previous_pair_combinations.iterkeys():
	
		cib = <combinatorial_info_block>previous_pair_combinations[key]
		fac = cib.np
		p = cib.p
	
	else:
	
		fac = falling_factorial(n, s) * binomial(n - s, m1 - s) * binomial(n - m1, m2 - s)
		p = <int *> malloc (sizeof(int) * n * fac)
		i = 0
		vertices = range(1, n + 1)
		perms = Permutations(vertices, s)
		for perm in perms:
			available_verts = [v for v in vertices if not v in perm]
			combs1 = Combinations(available_verts, m1 - s)
			first_one = True
			for comb1 in combs1:
				remaining_verts = [v for v in available_verts if not v in comb1]
				combs2 = Combinations(remaining_verts, m2 - s)
				first_two = True
				for comb2 in combs2:
					for j in range(s):
						if first_one:
							p[(i * n) + j] = <int> perm[j]
						else:
							p[(i * n) + j] = <int> 0
					for j in range(m1 - s):
						if first_two:
							p[(i * n) + s + j] = <int> comb1[j]
						else:
							p[(i * n) + s + j] = <int> 0
					for j in range(m2 - s):
						p[(i * n) + m1 + j] = <int> comb2[j]
					for j in range(n - m1 - m2 + s):
						p[(i * n) + m1 + m2 - s + j] = <int> 0
					first_one = False
					first_two = False
					i += 1			

		cib = combinatorial_info_block()
		cib.np = fac
		cib.p = p
		previous_pair_combinations[key] = cib
	
	if number_of:
		number_of[0] = fac

	return p

def get_pair_combinations (n, s, m1, m2):

	cdef int *p, np, i, j
	p = generate_pair_combinations(n, s, m1, m2, &np)
	return [[p[(i * n) + j] for j in range(n)] for i in range(np)]


previous_equal_pair_combinations = {}

cdef int *generate_equal_pair_combinations(int n, int s, int m, int *number_of):

	cdef int *p, fac, i, j, smallest

	# see if we've already generated it!
	key = (n, s, m)
	if key in previous_equal_pair_combinations.iterkeys():
	
		cib = <combinatorial_info_block>previous_equal_pair_combinations[key]
		fac = cib.np
		p = cib.p
	
	else:
	
		fac = falling_factorial(n, s) * binomial(n - s, m - s) * binomial(n - m, m - s) / 2
		p = <int *> malloc (sizeof(int) * n * fac)
		i = 0
		vertices = range(1, n + 1)
		perms = Permutations(vertices, s)
		for perm in perms:
			available_verts = [v for v in vertices if not v in perm]
			combs1 = Combinations(available_verts, m - s)
			first_one = True
			for comb1 in combs1:
				remaining_verts = [v for v in available_verts if not v in comb1]
				combs2 = Combinations(remaining_verts, m - s)
				smallest = min(comb1)
				first_two = True
				for comb2 in combs2:
					if min(comb2) < smallest:
						continue
					for j in range(s):
						if first_one:
							p[(i * n) + j] = <int> perm[j]
						else:
							p[(i * n) + j] = <int> 0
					for j in range(m - s):
						if first_two:
							p[(i * n) + s + j] = <int> comb1[j]
						else:
							p[(i * n) + s + j] = <int> 0
					for j in range(m - s):
						p[(i * n) + m + j] = <int> comb2[j]
					for j in range(n - m - m + s):
						p[(i * n) + m + m - s + j] = <int> 0
					first_one = False
					first_two = False
					i += 1			

		cib = combinatorial_info_block()
		cib.np = fac
		cib.p = p
		previous_equal_pair_combinations[key] = cib
	
	if number_of:
		number_of[0] = fac

	return p

def get_equal_pair_combinations (n, s, m):

	cdef int *p, np, i, j
	p = generate_equal_pair_combinations(n, s, m, &np)
	return [[p[(i * n) + j] for j in range(n)] for i in range(np)]






cdef class graph_block:
	cdef int n, len
	cdef void **graphs


def make_graph_block(graphs, n):

	gb = graph_block()
	gb.n = n
	gb.len = len(graphs)
	gb.graphs = <void **> malloc(gb.len * sizeof(void *))
	for i in range(gb.len):
		gb.graphs[i] = <void *> graphs[i]
	return gb

	
def print_graph_block(graph_block gb):

	for i in range(gb.len):
		g = <Flag ?> gb.graphs[i]
		print str(g)

#
# TODO: Make this function accept more than one type on s vertices.
#

def flag_products (graph_block gb, Flag tg, graph_block flags1, graph_block flags2):

	cdef int *p, np, *pp, *pf1, *pf2, *edges, *cur_edges
	cdef int n, s, m1, m2, ne, i, j, k, gi
	cdef int cnte, cnf1e, cnf2e
	cdef int has_type, has_f1
	cdef int f1index, f2index, *grb, equal_flags_mode, nzcount, row
	cdef Flag g, t, f1, f2
	
	rarray = numpy.zeros([0, 5], dtype=numpy.int)
	row = 0
	
	sig_on()
	
	n = gb.n
	s = tg.n
	m1 = flags1.n

	if not flags2 is None:

		equal_flags_mode = 0
		m2 = flags2.n
		p = generate_pair_combinations(n, s, m1, m2, &np)

	else:

		equal_flags_mode = 1
		m2 = flags1.n
		flags2 = flags1
		p = generate_equal_pair_combinations(n, s, m1, &np)

	cur_edges = <int *> malloc (sizeof(int) * MAX_NUMBER_OF_EDGE_INTS)
	pf1 = <int *> malloc (sizeof(int) * m1)
	pf2 = <int *> malloc (sizeof(int) * m2)
	grb = <int *> malloc (flags1.len * flags2.len * sizeof(int))

	for gi in range(gb.len):

		sig_on()
	
		g = <Flag> gb.graphs[gi]
	
		memset(grb, 0, flags1.len * flags2.len * sizeof(int))
	
		ne = g.ne
		edges = g._edges

		has_type = 0
		has_f1 = 0

		for i in range(np):
		
			pp = &p[(i * n)]
		
			if pp[0] != 0:
		
				for j in range(s):
					pf1[j] = pp[j]
					pf2[j] = pp[j]
						
				has_type = 0
				t = g.c_induced_subgraph(pf1, s)
				if tg.is_equal(t):
					has_type = 1
	
			if has_type == 0:
				continue
			
			if has_type and pp[s] != 0:
	
				has_f1 = 0
	
				for j in range(m1 - s):
					pf1[s + j] = pp[s + j]
	
				f1 = g.c_induced_subgraph(pf1, m1)
				f1.t = s
				f1.make_minimal_isomorph()

				for j in range(flags1.len):
					if f1.is_equal(<Flag> flags1.graphs[j]):
						has_f1 = 1
						f1index = j
						break
	
			if has_f1 == 0:
				continue
	
			for j in range(m2 - s):
				pf2[s + j] = pp[m1 + j]
	
			f2 = g.c_induced_subgraph(pf2, m2)
			f2.t = s
			f2.make_minimal_isomorph()
			
			for j in range(flags2.len):
				if f2.is_equal(<Flag> flags2.graphs[j]):
					f2index = j
					grb[(f1index * flags1.len) + f2index] += 1
					break

		if equal_flags_mode:
	
			nzcount = 0
			for i in range(flags1.len):
				for j in range(i, flags1.len):
					k = grb[(i * flags1.len) + j] + grb[(j * flags1.len) + i]
					if k != 0:
						nzcount += 1

			rarray.resize([row + nzcount, 5], refcheck=False)
			
			for i in range(flags1.len):
				for j in range(i, flags1.len):
					k = grb[(i * flags1.len) + j] + grb[(j * flags1.len) + i]
					if k != 0:
						rarray[row, 0] = gi
						rarray[row, 1] = i
						rarray[row, 2] = j
						rarray[row, 3] = k
						rarray[row, 4] = np * 2
						row += 1

		else:
	
			nzcount = 0
			for i in range(flags1.len):
				for j in range(flags2.len):
					k = grb[(i * flags1.len) + j]
					if k != 0:
						nzcount += 1

			rarray.resize([row + nzcount, 5], refcheck=False)
			
			for i in range(flags1.len):
				for j in range(flags2.len):
					k = grb[(i * flags1.len) + j]
					if k != 0:
						rarray[row, 0] = gi
						rarray[row, 1] = i
						rarray[row, 2] = j
						rarray[row, 3] = k
						rarray[row, 4] = np
						row += 1

	free(cur_edges)
	free(pf1)
	free(pf2)
	free(grb)

	sig_off()
	
	return rarray


def new_flag_products (Flag g, int s, int m1, int m2):
	"""
	Experimental function - not used for anything (yet).
	"""

	cdef int *p, np, *pp, *pf1, *pf2, *edges, *cur_edges
	cdef int n, ne, i, j, k, gi
	cdef int cnf1e, cnf2e
	cdef int num_flags1, f1index, num_flags2, f2index, equal_flags_mode
	cdef Flag f1, f2
	cdef void **flags1, **flags2

	sig_on()
		
	n = g.n
	ne = g.ne
	edges = g._edges

	num_flags1 = 0
	flags1 = NULL
	num_flags2 = 0
	flags2 = NULL

	if m1 == m2:
		equal_flags_mode = 1
		p = generate_equal_pair_combinations(n, s, m1, &np)

	else:
		equal_flags_mode = 0
		p = generate_pair_combinations(n, s, m1, m2, &np)
	
	cur_edges = <int *> malloc (sizeof(int) * MAX_NUMBER_OF_EDGE_INTS)
	pf1 = <int *> malloc (sizeof(int) * m1)
	pf2 = <int *> malloc (sizeof(int) * m2)

	for i in range(np):
	
		pp = &p[(i * n)]
	
		if pp[0] != 0:
	
			for j in range(s):
				pf1[j] = pp[j]
				pf2[j] = pp[j]
					
		if pp[s] != 0:

			for j in range(m1 - s):
				pf1[s + j] = pp[s + j]

			f1 = g.c_induced_subgraph(pf1, m1)
			f1.t = s
			f1.make_minimal_isomorph()

			for j in range(num_flags1):
				if f1.is_equal(<Flag> flags1[j]):
					f1index = j
					break
			else:
				num_flags1 += 1
				flags1 = <void **> realloc(flags1, num_flags1 * sizeof(void *))
				f1index = num_flags1 - 1
				Py_INCREF(f1)
				flags1[f1index] = <void *> f1

		for j in range(m2 - s):
			pf2[s + j] = pp[m1 + j]

		f2 = g.c_induced_subgraph(pf2, m2)
		f2.t = s
		f2.make_minimal_isomorph()
		
		if equal_flags_mode:
		
			for j in range(num_flags1):
				if f2.is_equal(<Flag> flags1[j]):
					f2index = j
					break
			else:
				num_flags1 += 1
				flags1 = <void **> realloc(flags1, num_flags1 * sizeof(void *))
				f2index = num_flags1 - 1 
				Py_INCREF(f2)
				flags1[f2index] = <void *> f2

		else:			

			for j in range(num_flags2):
				if f2.is_equal(<Flag> flags2[j]):
					f2index = j
					break
			else:
				num_flags2 += 1
				flags2 = <void **> realloc(flags2, num_flags2 * sizeof(void *))
				f2index = num_flags2 - 1
				Py_INCREF(f2)
				flags2[f2index] = <void *> f2

	for j in range(num_flags1):
		Py_DECREF(<Flag> flags1[j])

	for j in range(num_flags2):
		Py_DECREF(<Flag> flags2[j])
	
	free(flags1)
	free(flags2)

	free(cur_edges)
	free(pf1)
	free(pf2)

	sig_off()
	
	return