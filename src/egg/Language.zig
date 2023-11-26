const egg = @import("../egg.zig");

fn toy_language() type {
    return struct {
        Language: union(enum) { Add: [2]egg.Id, Sub: [2]egg.Id, Const: usize, Var: egg.Id },

        fn get_children() u32 {
            switch (self.Language) {
                Add => {
                    return &self.Add;
                },

                Sub => {
                    return &self.Sub;
                },
            }
        }
    };
}
