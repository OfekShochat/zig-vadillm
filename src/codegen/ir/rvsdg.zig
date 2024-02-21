// Notes:
// Regarding ematching: ematching should stop and backtrack as soon as it finds a special node
// i.e every node that is not a "simple node". The reason for this is that the ematching algorithm
// is not aware of control flow, and thus he can traverse the graph incorrectly and create wrong optimizations.
// General note: Our egraph is somewhat a mixed graph, that is to say, it consists of actually 2 graphs.
// The first and "outer" graph, is the egraph, the egraph is the "container" of the rvsdg.
// The rvsdg is the "inner" graph that is contained inside the egraph, it represents our control flow.
// Another thing to note is that while the egraph have some traversal rules, the rvsdg has its own traversal rules
// and those should be followed on each graph traversal as disregarding them will result in a wrong traversal of the tree
// due to the egraph being not aware of control flow at all.

const Instruction = @import("../instructions.zig").Instruction;
const std = @import("std");
const Type = @import("../types.zig").Type;
const Id = @import("../egg/egg.zig").Id;
// intra procedural

const Region = struct {
    id: Id,
    insts: []Node,
};

// Gama node represents an if-else-then statement it consists of condition which is just a region,
// and the evaluation of this region will affect the chosen case.
const GamaNode = struct {
    cond: Id,
    paths: []Id,
};

// Theta node represents a tail-controlled loop, i.e do-while,
// after each iteration the tail condition will be evaluated,
// and this result will decide wether to continue or break.
// the tail condition is just Region.
const ThetaNode = struct {
    tail_cond: Id,
    loop_body: Id,
};

// inter procedural

// Lambda node represents a function, the fucntion can get 0 or more arguments.
// The way those arguments are implemented in the graph is just like every other expression.
// That is to say, the argument should point to some eclass that represents an expression.
// In the egraph, the arguments will actually be represented as the childrens of the node,
// in oppose to the so called "logical" way to represent such a thing, the reason for this
// decision is the fact that egraph are directed with the opposite way to the flow of consumption
// lets suppose we have an add instruction, then its children will be its arguments, and not its outputs.
const LambdaNode = struct {
    arguments: []Id,
    function_body: Id,
};

const DeltaNode = struct {
    value: Region,
    inputs: []*Region,
    output: *Region,
};

const PhiNode = struct {
    input: Region,
    output: Region,
};

const OmegaNode = struct {
    region: Region,
};

// Optimaization barrier, acts as a state edge.
// the barrier will enforce the specific program structure that is described in the graph
// that is to say, no instruction-order related optimization will be performed on
// one block before and one block after this barrier
const OptBarrier = struct {
    code: Id,
};

const Node = union {
    simple: Instruction,
    gama: GamaNode,
    theta: ThetaNode,
    lambda: LambdaNode,
    delta: DeltaNode,
    phi: PhiNode,
    omega: OmegaNode,
};
