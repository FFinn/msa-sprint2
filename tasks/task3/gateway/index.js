import express from 'express';
import cors from 'cors';
import bodyParser from 'body-parser';
import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import {
  ApolloGateway,
  IntrospectAndCompose,
  RemoteGraphQLDataSource,
} from '@apollo/gateway';
import { renderPlaygroundPage } from '@apollographql/graphql-playground-html';

class HeaderForwardingDataSource extends RemoteGraphQLDataSource {
  willSendRequest({ request, context }) {
    const userId = context?.req?.headers?.userid;
    if (userId) {
      request.http.headers.set('userid', userId);
    }
  }
}

function getPlaygroundTab(scenario) {
  const endpoint = 'http://localhost:4000/';
  const query = `query {\n  bookingsByUser(userId: "user1") {\n    id\n    userId\n    hotelId\n    promoCode\n    discountPercent\n    hotel {\n      name\n      city\n    }\n  }\n}`;
  const headers = scenario === 'denied' ? { userid: 'user2' } : { userid: 'user1' };

  return [
    {
      endpoint,
      query,
      headers,
    },
  ];
}

const gateway = new ApolloGateway({
  supergraphSdl: new IntrospectAndCompose({
    subgraphs: [
      { name: 'booking', url: 'http://booking-subgraph:4001' },
      { name: 'hotel', url: 'http://hotel-subgraph:4002' },
    ],
  }),
  buildService: ({ url }) => new HeaderForwardingDataSource({ url }),
});

const server = new ApolloServer({ gateway, introspection: true });
await server.start();

const app = express();

app.get('/', (req, res) => {
  const scenario = req.query.scenario === 'denied' ? 'denied' : 'allowed';
  res
    .status(200)
    .type('html')
    .send(
      renderPlaygroundPage({
        endpoint: 'http://localhost:4000/',
        tabs: getPlaygroundTab(scenario),
        settings: {
          'editor.theme': 'dark',
          'request.credentials': 'same-origin',
          'schema.polling.enable': false,
        },
      }),
    );
});

app.use(
  '/',
  cors(),
  bodyParser.json(),
  expressMiddleware(server, {
    context: async ({ req }) => ({ req: req ?? { headers: {} } }),
  }),
);

app.listen(4000, () => {
  console.log('🚀 Gateway ready at http://localhost:4000/');
});
