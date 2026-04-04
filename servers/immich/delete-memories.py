import requests

# --- CONFIGURAÇÕES ---
IMMICH_URL = "http://localhost:9905"
API_KEY = "Z5TMXwJnTgfX6BwGyNQNQYbvUiWTiLPyfHdVhSlxIIY"
PREFIXO = "memory"

headers = {
    "Accept": "application/json",
    "x-api-key": API_KEY
}

def deletar_albuns_por_prefixo():
    # 1. Buscar todos os álbuns
    print("Buscando álbuns...")
    response = requests.get(f"{IMMICH_URL}/api/albums", headers=headers)
    
    if response.status_code != 200:
        print(f"Erro ao conectar: {response.status_code}")
        return

    albuns = response.json()
    sucesso = 0
    erros = 0

    # 2. Filtrar e deletar
    for album in albuns:
        album_id = album['id']
        album_name = album['albumName']

        if album_name.lower().startswith(PREFIXO.lower()):
            print(f"Deletando álbum: {album_name} (ID: {album_id})...")
            
            del_response = requests.delete(
                f"{IMMICH_URL}/api/albums/{album_id}", 
                headers=headers
            )

            if del_response.status_code in [200, 204]:
                print(f"✅ Álbum '{album_name}' removido.")
                sucesso += 1
            else:
                print(f"❌ Erro ao deletar '{album_name}': {del_response.status_code}")
                erros += 1

    print(f"\nTarefa concluída!")
    print(f"Álbuns deletados: {sucesso}")
    print(f"Erros encontrados: {erros}")

if __name__ == "__main__":
    deletar_albuns_por_prefixo()
