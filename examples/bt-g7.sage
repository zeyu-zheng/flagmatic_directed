P = ThreeGraphProblem()
P.forbid_subgraph("6:123124135345146256346", "6:123124134125135126136456", "6:123124134125136256356456", "6:123124134125135145126136146156", "6:123124134234125135245236146346")
P.forbid_homomorphic_images()
P.n = 6
x = polygen(QQ)
K = NumberField(x^2 - 13, 'x', embedding=RDF(3.6))
x = K.gen()
w1 = (5 - x)/6
w2 = (x - 2)/9
C = BlowupConstruction(ThreeGraphFlag("5:123124134234125135235145245"), weights=[w1,w1,w2,w2,w2], field=K)
P.set_extremal_construction(C)
P.compute_products()
P.solve_sdp(True)
P.change_solution_bases()
P.make_exact(2^30)
P.check_exact_bound()