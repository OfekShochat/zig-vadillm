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

// Please refer to the original RVSDG paper for a detailed overview of the blocks and their behavior

const Instruction = @import("../../instructions.zig").Instruction;
const std = @import("std");
const Type = @import("../../types.zig").Type;
const Id = @import("../../egg/egg.zig").Id;
// intra procedural

pub const Region = struct {
    id: Id,
    insts: []Node,
};

// Gama node represents an if-else-then statement it consists of condition which is just a region,
// and the evaluation of this region will affect the chosen case.
pub const GamaNode = struct {
    node_id: Id,
    cond: Id,
    paths: []Id,
};

// We need some way to denote that we reached the end of the diveres control flow region
// and reached the end of the if statement, therefore we intoduce this block to our rvsdg.
// this block is the last block of all the paths of the GamaNode. technically it is possible
// to have an if statement without an exit node, for example in the next if statement we'll have no exit node:
// if (statement):
//      return 1;
// else:
//      return 0
// Due to the fact that the control flow ends in each on of the statements, we don't need to have an ExitNode.
// int a = 0;
// if (statement):
//      a = 1;
// else:
//      a = 2;
// print(a)
//
// in this if statement, we would need an endnode because our control flow is reunited in the end and we need to know
// where it happens. the exitNode will point to print(a) in this case.
pub const GamaExitNode = struct {
    unified_flow_node: Id,
};

// Theta node representsa tail-controlled loop, i.e do-while,
// after each iteration the tail condition will be evaluated,
// and this result will decide wether to continue or break.
// the tail condition is just Region.
pub const ThetaNode = struct {
    node_id: Id,
    tail_cond: Id,
    loop_body: Id,
};

// inter procedural

// Lambda node represents a function, the fucntion can get 0 or more arguments.
// The way those arguments are implemented in the graph is just like every other expression.
// That is to say, the argument should point to some eclass that represents an expression.
// In the egraph, the arguments will actually be represented as the childrens of the node,
// in oppose to the so called "logical" way to represent such a thing, the reason for this
// decision is the factthat egraph are directed with the opposite way to the flow of consumption
// lets suppose we have an add instruction, then its children will be its arguments, and not its outputs.
pub const LambdaNode = struct {
    node_id: Id,
    arguments: []Id,
    output: Id,
    function_body: Id,
};

pub const DeltaNode = struct {
    node_id: Id,
    value: Region,
    inputs: []*Region,
    output: *Region,
};

pub const PhiNode = struct {
    node_id: Id,
    input: Region,
    output: Region,
};

pub const OmegaNode = struct {
    node_id: Id,
    region: Region,
};

// Optimaization barrier, acts as a state edge.
// the barrier will enforce the specific program structure that is described in the graph
// that is to say, no instruction-order related optimization will be performed on
// one block before and one block after this barrier
pub const OptBarrier = struct {
    code: Id,
};

pub const Get = struct {
    output_id: Id,
};

pub const applyNode = struct {
    function: Id,
    arguments: []Id,
};

pub const Node = union(enum) {
    simple: Instruction,
    gama: GamaNode,
    theta: ThetaNode,
    lambda: LambdaNode,
    delta: DeltaNode,
    phi: PhiNode,
    omega: OmegaNode,
    gamaExit: GamaExitNode,
};
