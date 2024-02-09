const Instruction = @import("../instructions.zig").Instruction;
const std = @import("std");
const Type = @import("../types.zig").Type;
// intra procedural

const Region = struct {
    region_parents: []Edge,
    insts: []Node,
};

const GamaNode = struct {
    cond: []Instruction,
    cond_eval_map: std.HashMap(u32, u32),
    paths: []Region,
    exit_node: *Node,
    parents: []Edge,
};

const ThetaNode = struct {
    tail_cond: []Instruction,
    loop_body: Region,
    exit_node: *Node,
    parents: []Edge,
};

// inter procedural

const LambdaNode = struct {
    arguments: []Type,
    function_body: Region,
    exit_node: *Node,
    parents: []*Edge,
};

const DeltaNode = struct {
    value: Region,
    inputs: []*Region,
    output: *Region,
    parents: []*Edge,
};

const PhiNode = struct {
    input: Region,
    output: Region,
    parents: []*Edge,
};

const OmegaNode = struct {
    region: Region,
    parents: []*Edge,
};

const Edge = struct {
    state: bool,
    end: *Region,
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
