// Lo mismo que erp-app/src/modules/presupuestos/cifrado.ts, con WebCrypto (decisiones/erp-cliente.md → Dos bases).
const sha256 = async (texto: string) => new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto)));

export async function huellaDe(link: string): Promise<string> {
  const h = await sha256(`huella:${link}`);
  return Array.from(h, (b) => b.toString(16).padStart(2, "0")).join("");
}

// base64 de iv (12) ‖ cifrado ‖ tag (16): AES-GCM de WebCrypto espera el tag pegado al final.
export async function descifrar(link: string, copia: string): Promise<string> {
  const bytes = Uint8Array.from(atob(copia), (c) => c.charCodeAt(0));
  const llave = await crypto.subtle.importKey("raw", await sha256(`llave:${link}`), "AES-GCM", false, ["decrypt"]);
  const claro = await crypto.subtle.decrypt({ name: "AES-GCM", iv: bytes.slice(0, 12) }, llave, bytes.slice(12));
  return new TextDecoder().decode(claro);
}
