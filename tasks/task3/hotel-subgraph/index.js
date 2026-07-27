import { ApolloServer } from '@apollo/server';
import { startStandaloneServer } from '@apollo/server/standalone';
import { buildSubgraphSchema } from '@apollo/subgraph';
import gql from 'graphql-tag';

const hotelApiUrl = process.env.HOTEL_API_URL || 'http://monolith:8080/api/hotels';

async function getHotel(id) {
  try {
    const response = await fetch(`${hotelApiUrl}/${encodeURIComponent(id)}`);
    if (!response.ok) {
      console.warn(`Hotel ${id} was not found in monolith REST API (HTTP ${response.status})`);
      return null;
    }
    const hotel = await response.json();
    const resolvedHotel = {
      id: hotel.id,
      // Monolith REST does not expose a dedicated hotel name field.
      // For Task 3 we use the fixture description as the display name.
      name: hotel.description ?? `Hotel ${hotel.id}`,
      city: hotel.city,
      stars: hotel.stars ?? Math.round(hotel.rating ?? 0),
    };
    console.info(`Resolved hotel ${id} from monolith REST`);
    return resolvedHotel;
  } catch (error) {
    console.warn(`Не удалось получить отель ${id}: ${error.message}`);
    return null;
  }
}

const typeDefs = gql`
  type Hotel @key(fields: "id") {
    id: ID!
    name: String
    city: String
    stars: Int
  }

  type Query {
    hotelsByIds(ids: [ID!]!): [Hotel]
  }
`;

const resolvers = {
  Hotel: {
    __resolveReference: async ({ id }) => {
      return getHotel(id);
    },
  },
  Query: {
    hotelsByIds: async (_, { ids }) => {
      return Promise.all(ids.map(getHotel));
    },
  },
};

const server = new ApolloServer({
  schema: buildSubgraphSchema([{ typeDefs, resolvers }]),
});

startStandaloneServer(server, {
  listen: { port: 4002 },
}).then(() => {
  console.log('✅ Hotel subgraph ready at http://localhost:4002/');
});
