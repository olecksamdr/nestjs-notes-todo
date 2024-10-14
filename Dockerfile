# https://www.tomray.dev/nestjs-docker-production
FROM node:12.22.12-alpine3.14

# Create app directory
WORKDIR /app

# Copy application dependency manifests to the container image.
# A wildcard is used to ensure copying both package.json AND package-lock.json (when available).
# Copying this first prevents re-running npm install on every code change.
COPY --chown=node:node package*.json ./

# Install app dependencies using the `npm ci` command instead of `npm install`
RUN npm install

# This is a common pattern in Dockerfiles (in all languages).
# The npm install step takes a long time,
# but you only need to run it when the package dependencies change.
# So it's typical to see one step that just installs dependencies,
# and a second step that adds the actual application,
#  because it makes rebuilding the container go faster.

# Copy app source
COPY --chown=node:node . .

RUN npm run build

# Use the node user from the image (instead of the root user)
USER node

# Start the server using the production build
CMD [ "node", "dist/src/main.js" ]
