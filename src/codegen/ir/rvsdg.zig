const Instruction = @import("../instructions.zig").Instruction;
const std = @import("std");
const Type = @import("../types.zig").Type;
// intra procedural

const Region = struct {
    region_parents: []*Region,
    insts: []Node,
};

// Gama node represents an if-else-then statement it consists of condition which is just a region,
// and the evaluation of this region will affect the chosen case.
const GamaNode = struct {
    cond: Region,
    cases: []Region,
    outputs: []Region,
};

// Theta node represents a tail-controlled loop, i.e do-while,
// after each iteration the tail condition will be evaluated,
// and this result will decide wether to continue or break.
// the tail condition is just Region.
const ThetaNode = struct {
    tail_cond: []Region,
    loop_body: Region,
    outputs: []Region,
};

// inter procedural

const LambdaNode = struct {
    arguments: []Type,
    function_body: Region,
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
    inputs: []*Region,
    output: []*Region,
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
