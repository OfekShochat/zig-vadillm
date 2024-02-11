const Instruction = @import("../instructions.zig").Instruction;
const std = @import("std");
const Type = @import("../types.zig").Type;
// intra procedural

const Region = struct {
    region_parents: []*Region,
    insts: []Node,
};

const GamaNode = struct {
    cond: []Instruction,
    cases: []Region,
    outputs: []Region,
};

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

const Node = union {
    simple: Instruction,
    gama: GamaNode,
    theta: ThetaNode,
    lambda: LambdaNode,
    delta: DeltaNode,
    phi: PhiNode,
    omega: OmegaNode,
};
