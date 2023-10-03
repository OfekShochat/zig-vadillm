const MachineInst = @import("MachineInst.zig").MachineInst;
const Operand = @import("regalloc.zig").Operand;
const RegClass = @import("regalloc.zig").RegClass;
const std = @import("std");
const Index = @import("../../ir.zig").Index;
const regalloc = @import("regalloc.zig").regalloc;
const types = @import("../types.zig");

pub const BinOp = struct {
    lhs : Operand,
    rhs : Operand,

    pub fn getAllocatableOperands(self: *BinOp, operands_out: *std.ArrayList(regalloc.Operand)) !void {
        operands_out.push(self.lhs);
        operands_out.push(self.rhs);
    }

    pub fn regTypeForClass(class: regalloc.RegClass) types.Type {
        return class.int;
    }

    pub fn getBranches() *std.ArrayListUnmanaged {
        return 0;
    }

    pub fn init(self: *BinOp, lhs : Operand, rhs : Operand) MachineInst{
        self.lhs = lhs;
        self.rhs = rhs;

        var inst = MachineInst {
            .getAllocatableOperands = getAllocatableOperands,
            .regTypeForClass = regTypeForClass,
            .getBranches = getBranches,
        };

        return inst;
    }
};

pub const call = struct {
    func: Index,
    args: *std.ArrayListUnmanaged(Operand),

    pub fn getAllocatableOperands(self: *call, operands_out: *std.ArrayList(regalloc.Operand)) !void {
        operands_out = self.args;
    }

    pub fn regTypeForClass(class: regalloc.RegClass) types.Type {
        return class.vector;
    }

    pub fn getBranches(self: *call, branches: *std.ArrayListUnmanaged) !void {
        branches.push(self.func);
    }

    pub fn init(self: *BinOp, func: Index, args: *std.ArrayListUnmanaged) MachineInst {
        self.func = func;
        self.args = args;

        return MachineInst {
            .getAllocatableOperands = getAllocatableOperands,
            .regTypeForClass = regTypeForClass,
            .getBranches = getBranches,
        };
    }
};

pub const brif = struct {
    cond: Index,
    cond_true: Index,
    cond_false: Index,

    pub fn getAllocatableOperands(operands_out: *std.ArrayList(regalloc.Operand)) !void {
        operands_out.push(brif.cond_true);
        operands_out.push(brif.cond_false);
    }

    pub fn regTypeForClass(class: regalloc.RegClass) types.Type {
        return class.vector;
    }

    pub fn getBranches(self: *brif, branches: *std.ArrayListUnmanaged) !void {
        branches.push(self.cond_true);
        branches.push(self.cond_false);
    }

    pub fn init(self: *brif, cond_true: Index, cond_false: Index) MachineInst {
        self.cond_true = cond_true;
        self.cond_false = cond_false; 

        return MachineInst {
            .getAllocatableOperands = getAllocatableOperands,
            .regTypeForClass = regTypeForClass,
            .getBranches = getBranches,
        };
    }
};

pub const jump = struct {
    block: Index,

    pub fn getAllocatableOperands(self: *jump, operands_out: *std.ArrayList(regalloc.Operand)) !void {
        operands_out.push(self.block);
    }

    pub fn regTypeForClass(class: regalloc.RegClass) types.Type {
        return class.int;
    }

    pub fn getBranches(self: *jump, branches: *std.ArrayListUnmanaged) !void {
        branches.push(self.block);
    }

    pub fn init(self: *jump, block: Index) MachineInst {
        self.block = block;

        return MachineInst {
            .getAllocatableOperands = getAllocatableOperands,
            .regTypeForClass = regTypeForClass,
            .getBranches = getBranches,
        };
    }
};