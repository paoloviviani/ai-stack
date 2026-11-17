FROM node:24-bookworm-slim

WORKDIR /driver
COPY package.json ./
RUN npm install --no-audit --no-fund
COPY driver.mjs .

# The negative control: prove the daemon is unreachable from this network
# side before anything else runs.
CMD ["node", "driver.mjs"]
