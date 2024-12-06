import os
import json
from web3 import Web3
from eth_abi import decode
from typing import List, Dict, Any, Union

class LocalTxnParser:
    def __init__(self, web3: Web3, abis_directory: str):
        self.web3 = web3
        self.abis_directory = abis_directory
        self.contract_abis = {}
        self.function_signatures = {}
        self._load_abis()
    
    def _get_function_selector(self, func_name: str, input_types: list) -> str:
        signature = f"{func_name}({','.join(input_types)})"
        selector = Web3.keccak(text=signature)[:4].hex()
        return "0x" + selector
    
    def _parse_input_tuple(self, input) -> str:
        input_types = ""
        for component in input['components']:
            input_types += (f"{component['type']},")
        input_types = f"({input_types[:-1]})[]"
        return input_types
    
    def _load_abis(self):
        for filename in os.listdir(self.abis_directory):
            if filename.endswith('.json'):
                contract_name = filename[:-5]
                filepath = os.path.join(self.abis_directory, filename)
                
                with open(filepath, 'r') as f:
                    abi = json.load(f)
                    self.contract_abis[contract_name] = abi
                    
                    for func in abi:
                        if func['type'] == 'function':
                            try:
                                inputs = []
                                for input in func['inputs']:
                                    if input['type'] != 'tuple[]':
                                        inputs.append(input['type'])
                                    else:
                                        tuple_types = self._parse_input_tuple(input)
                                        inputs.append(tuple_types)
                                        # overwrite the tuple[] object with the actual types
                                        input['type'] = tuple_types
                                func_selector = self._get_function_selector(func['name'], inputs)
                                if func_selector not in self.function_signatures:
                                    self.function_signatures[func_selector] = (contract_name, func)
                                else:
                                   (existing_contract, func) = self.function_signatures[func_selector]
                                   existing_contract += f" || {contract_name}"
                                   self.function_signatures[func_selector] = (existing_contract, func)
                            except Exception as e:
                                print(f"Warning: Could not process function {func['name']}: {e}")

    def parse_txn(self, target: str, data: str) -> Dict[str, Any]:
        target = Web3.to_checksum_address(target)
        func_signature = data[:10]
        
        if func_signature not in self.function_signatures:
            return {
                "status": "error",
                "message": f"Unknown function signature: {func_signature}",
                "target": target,
                "signature": func_signature
            }
            
        contract_name, func_abi = self.function_signatures[func_signature]
        
        try:
            input_types = [param['type'] for param in func_abi['inputs']]
            input_names = [param['name'] for param in func_abi['inputs']]
            parameters_data = data[10:]
        
            if not parameters_data:
                parameters = {}
            else:
                decoded = decode(input_types, bytes.fromhex(parameters_data))
                parameters = dict(zip(input_names, decoded))

                for key, value in parameters.items():
                    if isinstance(value, bytes):
                        parameters[key] = '0x' + value.hex()
                
                # certain transactions we can parse further

                # decode the underlying call that is being scheduled/executed
                if contract_name == "EtherfiTimelock":
                    transaction = {}
                    if func_abi['name'] == 'schedule':
                        transaction = self.parse_txn(parameters['target'], parameters['data'])
                    else:
                        transaction = self.parse_txn(parameters['target'], parameters['payload'])
                    return {
                        "contract": contract_name,
                        "function": func_abi['name'],
                        "target": target,
                        "transaction": transaction
                    }
                

                # decode the call being made with the upgrade
                if (func_abi['name'] == "upgradeAndCall") and (parameters['data'] != '0x'):
                    parameters['data'] = self.parse_txn(target, parameters['data'])
                    return {
                        "contract": contract_name,
                        "function": func_abi['name'],
                        "target": target,
                        "parameters": parameters
                    }

            print(contract_name)
            return {
                "contract": contract_name,
                "function": func_abi['name'],
                "target": target,
                "parameters": parameters
            }
        except Exception as e:
            return {
                "status": "error",
                "message": f"Error decoding parameters: {str(e)}",
                "target": target,
                "signature": func_signature
            }

    def parse_transaction_batch(self, transactions_data: Union[str, Dict]) -> List[Dict[str, Any]]:
        # Parse JSON if string input
        if isinstance(transactions_data, str):
            data = json.loads(transactions_data)
        else:
            data = transactions_data

        results = []
        for _, txn in enumerate(data['transactions'], 1):
            parsed_result = self.parse_txn(
                target=txn['to'],
                data=txn['data']
            )
            parsed_result['file_source'] = data.get('source_file', 'unknown')
            results.append(parsed_result)

        return results

    def process_directory(self, transactions_dir: str) -> Dict[str, List[Dict[str, Any]]]:
        all_results = {}
        
        for filename in os.listdir(transactions_dir):
            if not filename.endswith('.json'):
                continue
                
            file_path = os.path.join(transactions_dir, filename)
            
            with open(file_path, 'r') as f:
                transactions_data = json.load(f)
                transactions_data['source_file'] = filename
                
            results = self.parse_transaction_batch(transactions_data)
            all_results[filename] = results
                
        return all_results

# custom decoder for bytes objects
class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj: Any) -> Any:
        if isinstance(obj, bytes):
            return '0x' + obj.hex()
        return super().default(obj)

def main():
    # Initialize the parser
    web3 = Web3(Web3.HTTPProvider('https://eth.llamarpc.com', request_kwargs={'timeout': 120}))
    current_dir = os.path.dirname(os.path.abspath(__file__))
    abis_dir = os.path.join(current_dir, 'OFTContractABIs')
    parent_dir = os.path.dirname(current_dir)
    transactions_dir = os.path.join(parent_dir, 'output')
    
    parser = LocalTxnParser(web3, abis_dir)

    # Process entire directory
    results = parser.process_directory(transactions_dir)
    
    # Write results to output file
    output_path = os.path.join(current_dir, 'parsed-transactions.json')
    with open(output_path, 'w') as f:
        json.dump(results, f, indent=2, cls=CustomJSONEncoder)
        
    print(f"\nProcessed transactions written to {output_path}")
    
    # Print summary
    print("\nProcessing Summary:")
    for filename, file_results in results.items():
        print(f"{filename}: {len(file_results)} transactions processed")

if __name__ == "__main__":
    main()
