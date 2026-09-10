"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";

// Solo se renderiza para quien tiene el permiso `_todas` (o `obras_transferir`
// en obras). Por default el listado muestra lo propio; "Todos" agrega lo ajeno
// con badge. Vive en la URL para que el server refetchee con el alcance nuevo.
export function AlcanceToggle() {
  const router = useRouter();
  const pathname = usePathname();
  const sp = useSearchParams();
  const actual = sp.get("alcance") === "todos" ? "todos" : "propios";

  function set(a: "propios" | "todos") {
    const p = new URLSearchParams(sp);
    if (a === "propios") p.delete("alcance");
    else p.set("alcance", a);
    const qs = p.toString();
    router.push(qs ? `${pathname}?${qs}` : pathname);
  }

  return (
    <div className="inline-flex overflow-hidden rounded-md border border-border">
      {(["propios", "todos"] as const).map((a) => (
        <button
          key={a}
          type="button"
          onClick={() => set(a)}
          className={`tap-target px-3 text-sm ${
            actual === a
              ? "bg-brand-50 font-semibold text-brand-700"
              : "text-text-tertiary hover:bg-bg-subtle"
          }`}
        >
          {a === "propios" ? "Míos" : "Todos"}
        </button>
      ))}
    </div>
  );
}
