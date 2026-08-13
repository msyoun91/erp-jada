"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function toggleWidget(widgetId: string, visible: boolean) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { success: false as const, error: "No autorizado" };

  const { error } = await supabase
    .from("usuario_widgets")
    .upsert(
      { usuario_id: user.id, widget_id: widgetId, visible },
      { onConflict: "usuario_id,widget_id" }
    );

  if (error) return { success: false as const, error: error.message };

  revalidatePath("/");
  return { success: true as const };
}
