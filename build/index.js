import lib from "@saturn-chain/smart-contract";
const SmartContracts = lib.default? lib.default.SmartContracts: lib.SmartContracts;
import combined from "./combined.json" assert { type: "json" }; // still marked experimental
export default SmartContracts.load(combined);
