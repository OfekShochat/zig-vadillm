const std = @import("std");

pub const CodePoint = struct {
    point: u32,

    pub fn invalidMax() CodePoint {
        return CodePoint{ .point = std.math.maxInt(u32) };
    }

    pub fn toArrayIndex(self: CodePoint) u32 {
        return self.point / 2;
    }

    pub fn isBefore(self: CodePoint, other: CodePoint) bool {
        return self.point < other.point;
    }

    pub fn isBeforeOrAt(self: CodePoint, other: CodePoint) bool {
        return self.point <= other.point;
    }

    pub fn isAfter(self: CodePoint, other: CodePoint) bool {
        return self.point > other.point;
    }

    pub fn isAfterOrAt(self: CodePoint, other: CodePoint) bool {
        return self.point >= other.point;
    }

    pub fn isSame(self: CodePoint, other: CodePoint) bool {
        return self.point == other.point;
    }

    pub fn getEarly(self: CodePoint) CodePoint {
        return CodePoint{ .point = (self.point / 2) * 2 };
    }

    pub fn getLate(self: CodePoint) CodePoint {
        return CodePoint{ .point = self.getEarly().point + 1 };
    }

    pub fn getJustBefore(self: CodePoint) CodePoint {
        return CodePoint{ .point = self.point - 1 };
    }

    pub fn getJustAfter(self: CodePoint) CodePoint {
        return CodePoint{ .point = self.point + 1 };
    }

    pub fn getNextInst(self: CodePoint) CodePoint {
        return CodePoint{ .point = self.getEarly().point + 2 };
    }

    pub fn getPrevInst(self: CodePoint) CodePoint {
        return CodePoint{ .point = self.getEarly().point - 2 };
    }

    pub fn compareFn(self: CodePoint, other: CodePoint) std.math.Order {
        if (self.isBefore(other)) {
            return .lt;
        }

        if (self.isAfter(other)) {
            return .gt;
        }

        return .eq;
    }
};

pub const Index = u32;
