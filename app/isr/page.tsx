import { revalidatePath } from "next/cache";
import { getPokemonAction } from "../actions";
import { FreshnessTimer } from "./timer";

// ISR: Revalidate this page at most once every 10 seconds
export const revalidate = 10;

async function revalidateAction() {
  "use server";
  revalidatePath("/isr");
}

async function getPokemon() {
  // Generate random Pokemon ID from first generation (1-151)
  const randomId = Math.floor(Math.random() * 151) + 1;
  // Use server action with ISR revalidation (10 seconds)
  return await getPokemonAction(randomId, 10);
}

export default async function ISRDemo() {
  const pokemon = await getPokemon();
  const generatedAt = Date.now();

  return (
    <div>
      <h1>ISR Demo</h1>
      <p>Pokemon ID: {pokemon.id}</p>
      <p>Name: {pokemon.name}</p>
      <p>Types: {pokemon.type.join(", ")}</p>
      <FreshnessTimer generatedAt={generatedAt} />
      <form action={revalidateAction}>
        <button type="submit">Revalidate</button>
      </form>
    </div>
  );
}
