import os
import secrets
from cryptography.fernet import Fernet

def generate_env():
    env_path = ".env"
    if os.path.exists(env_path):
        print(".env already exists. Skipping generation to prevent overwriting existing keys.")
        return

    print("Generating secure keys for .env...")
    jwt_secret = secrets.token_hex(32)
    fernet_key = Fernet.generate_key().decode('utf-8')

    content = f"""# BloodSense Environment Variables
JWT_SECRET={jwt_secret}
FERNET_KEY={fernet_key}

# Database Configurations
DB_USER=postgres
DB_PASSWORD=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=bloodsense

# Caching Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
"""
    with open(env_path, "w") as f:
        f.write(content)
    print("Successfully created .env file with secure generated keys!")

if __name__ == "__main__":
    generate_env()
