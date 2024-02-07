const Instruction = @import("../instructions.zig").Instruction;
const std = @import("std");

// intra procedural

const Region = struct {
    insts: []Node,
};

const GamaNode = struct {
    cond: []Instruction,
    cond_eval_map: std.HashMap(u32, u32),
    paths: []Region,
    exit_node: anyopaque,
};

const ThetaNode = struct {
    tail_cond: []Instruction,
    loop_body: Region,
    exit_node: anyopaque,
};

// inter procedural

const LambdaNode = struct {
    arguments: [],
    function_body: Region,
    output: ,
};

const DeltaNode = struct {

}

const PhiNode = struct {

}

const OmegaNode = struct {

}

const Node = union {
    simple: Instruction,
    gama: GamaNode,
    theta: ThetaNode,
    lambda: LambdaNode,
    delta: DeltaNodes,
    phi: PhiNode,
    omega: OmegaNode,
};
