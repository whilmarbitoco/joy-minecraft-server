FROM itzg/minecraft-bedrock-server:latest

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
