"use server";

import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

// Pasos del tutorial que el usuario ya vio. La RLS acota a sus propias filas.
export async function getTutorialVistos(): Promise<string[]> {
  const supabase = await createClient();
  const { data } = await supabase.from("usuario_tutorial").select("paso");
  return (data ?? []).map((f) => f.paso);
}

const pasosSchema = z.array(z.string().min(1).max(80)).min(1);

// Sin `revalidatePath` ni error visible: es la contabilidad de qué se le mostró, no una acción del usuario. El peor
// caso de un fallo es que el tutorial se vuelva a ofrecer.
export async function marcarTutorialVisto(pasos: string[]) {
  const parsed = pasosSchema.safeParse(pasos);
  if (!parsed.success) return;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return;
  await supabase
    .from("usuario_tutorial")
    .upsert(parsed.data.map((paso) => ({ usuario_id: user.id, paso })), { onConflict: "usuario_id,paso" });
}
