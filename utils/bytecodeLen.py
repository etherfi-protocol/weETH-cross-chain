if __name__ == "__main__":
    # 
    hex_string_1 = "" 
    # 
    hex_string_2 = ""

    bytes_from_string_1 = bytes.fromhex(hex_string_1.replace('0x', ''))

    print("bytes from hex string 1")
    print(len(bytes_from_string_1))

    bytes_from_string_2 = bytes.fromhex(hex_string_2.replace('0x', ''))
    
    print("bytes from hex string 2")
    print(len(bytes_from_string_2))
