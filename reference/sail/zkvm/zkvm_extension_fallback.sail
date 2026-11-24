// The Lean model is generated from a subset of modules; extensions whose
// currentlyEnabled clause is not built are never enabled. Extensions with their own
// clause match that clause first, so this module must come after every extension module.
function clause currentlyEnabled(ext) = {
  assert(not(hartSupports(ext)), "extension " ^ extensionName(ext) ^ " is supported but its module is not in this build");
  false
}
