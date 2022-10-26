FROM gcr.io/google-samples/node-hello:1.0 as app

FROM kontainapp/runenv-node

COPY --from=app /server.js /server.js

CMD [ "node", "/server.js" ]


