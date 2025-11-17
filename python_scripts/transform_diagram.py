from graphviz import Digraph

dot = Digraph(comment='Triangle Transformation Pipeline')
dot.attr(rankdir='LR')

# Nodes
dot.node('M', 'Model Vertex (v0, v1, v2)')
dot.node('S', 'Scale')
dot.node('R', 'Rotate (Model Rotation)')
dot.node('T', 'Translate (Model Position)')
dot.node('W', 'World Vertex')
dot.node('C_T', 'Translate to Camera Center (p - C)')
dot.node('C_R', 'Rotate (Camera R^T)')
dot.node('Proj', 'Project (x*f/z, y*f/z)')
dot.node('P', 'Projected Triangle Vertex')

# Correct edges: list of 2-tuples (from, to)
edges = [
    ('M', 'S'),
    ('S', 'R'),
    ('R', 'T'),
    ('T', 'W'),
    ('W', 'C_T'),
    ('C_T', 'C_R'),
    ('C_R', 'Proj'),
    ('Proj', 'P')
]

dot.edges(edges)

dot.render('/tmp/triangle_pipeline', format='png', cleanup=False)
