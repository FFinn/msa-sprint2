import { ApolloServer } from '@apollo/server';
import { startStandaloneServer } from '@apollo/server/standalone';
import { buildSubgraphSchema } from '@apollo/subgraph';
import gql from 'graphql-tag';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';
import { fileURLToPath } from 'node:url';

const protoPath = fileURLToPath(new URL('./booking.proto', import.meta.url));
const packageDefinition = protoLoader.loadSync(protoPath, {
  keepCase: false,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
});
const bookingProto = grpc.loadPackageDefinition(packageDefinition).booking;
const bookingClient = new bookingProto.BookingService(
  process.env.BOOKING_GRPC_ADDRESS || 'booking-service:9090',
  grpc.credentials.createInsecure(),
);

function listBookings(userId) {
  return new Promise((resolve, reject) => {
    bookingClient.ListBookings({ userId }, (error, response) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(response.bookings);
    });
  });
}

const typeDefs = gql`
  type Booking @key(fields: "id") {
    id: ID!
    userId: String!
    hotelId: String!
    promoCode: String
    discountPercent: Float
    hotel: Hotel!
  }

  extend type Hotel @key(fields: "id") {
    id: ID! @external
  }

  type Query {
    bookingsByUser(userId: String!): [Booking]
  }

`;

const resolvers = {
  Query: {
    bookingsByUser: async (_, { userId }, { req }) => {
      const authenticatedUserId = req?.headers?.userid;
      if (!authenticatedUserId || authenticatedUserId !== userId) {
        console.warn(`Доступ к бронированиям ${userId} отклонён`);
        return [];
      }

      const bookings = await listBookings(userId);
      console.info(`Возвращено бронирований: ${bookings.length}`);
      return bookings;
    },
  },
  Booking: {
    hotel: (booking) => ({ __typename: 'Hotel', id: booking.hotelId }),
  },
};

const server = new ApolloServer({
  schema: buildSubgraphSchema([{ typeDefs, resolvers }]),
});

startStandaloneServer(server, {
  listen: { port: 4001 },
  context: async ({ req }) => ({ req: req ?? { headers: {} } }),
}).then(() => {
  console.log('✅ Booking subgraph ready at http://localhost:4001/');
});
