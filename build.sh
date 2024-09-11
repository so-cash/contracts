# Do not use version 0.8.20 for the moment because Kerleano and PocrNet do not support the Shanghai fork (EIP-3855)
SOLC=`(which solc>/dev/null && which solc) || echo /usr/local/bin/solc-v0.8.17`
if [ ! -x "$SOLC" ]
then
  SOLC="docker run -v $PWD:/work -w /work ethereum/solc:0.8.17"
fi
echo "Using solc as \"$SOLC\""
$SOLC --version
$SOLC -o build --optimize --combined-json abi,bin,bin-runtime --overwrite --base-path . --include-path ./node_modules src/*/*.sol
if [ $? -eq 0 ]
then
  echo "- Create index.js and index.d.ts files"
  # replace by an ESM compatible js code
  # echo 'const lib = require("@saturn-chain/smart-contract");' > build/index.js
  # echo 'const SmartContracts = lib.default? lib.default.SmartContracts: lib.SmartContracts;' >> build/index.js
  # echo 'const combined = require("./combined.json");' >> build/index.js
  # echo 'module.exports = SmartContracts.load(combined);' >> build/index.js
  echo 'import lib from "@saturn-chain/smart-contract";' > build/index.js
  echo 'const SmartContracts = lib.default? lib.default.SmartContracts: lib.SmartContracts;' >> build/index.js
  echo 'import combined from "./combined.json" assert { type: "json" }; // still marked experimental' >> build/index.js
  # The following lines do not work with NUXT because it messes with the import.meta.url
  # echo '// import {createRequire} from "module";' >> build/index.js
  # echo '// const require = createRequire(import.meta.url);' >> build/index.js
  # echo '// const combined = require("./combined.json");' >> build/index.js
  echo 'export default SmartContracts.load(combined);' >> build/index.js


  echo 'import { SmartContracts } from "@saturn-chain/smart-contract"' > build/index.d.ts
  echo 'declare const _default: SmartContracts;' >> build/index.d.ts
  echo 'export default _default;' >> build/index.d.ts

  echo "- Verify compilation and script by displaying the loaded contracts"
  # node -e 'console.log("  > "+require("./build/index.js").names().join("\n  > "))'
  node -e 'import("./build/index.js").then(sc=>console.log("  > "+sc.default.names().join("\n  > ")))'
else
  echo "Compilation failed"
  exit 1
fi
