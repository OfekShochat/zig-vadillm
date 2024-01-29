# Vadillm - A Small Optimizing Compiler

Vadillm is a small optimizing compiler focusing on simplicity - mostly. It implements E-graphs and E-matching (that is based on the 2007 paper and egg's), has two IRs, though currently only the second one is not scheduled to be reworked; and... More.

Note the code is not nearly optimal or pretty, though, it does have some nice things. Note, only `src/codegen/` and `src/egg/` are somewhat finalized in structure. The plan is to either use the current first IR as a 'guideline' or throw it away in favor of an RVSDG one that will use the egraphs implementation as its base structure. 
