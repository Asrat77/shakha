import { useEffect, useRef, useState } from "react";

const API = import.meta.env.VITE_API_URL || "http://localhost:3000";
const AUTH = `${API}/auth/shakha`;
const RETURN_TO = `${window.location.origin}/login`;

function signIn(provider) {
  window.location = `${AUTH}/${provider}?return_to=${encodeURIComponent(RETURN_TO)}`;
}

export default function App() {
  const [token, setToken] = useState(() => localStorage.getItem("token"));
  const [user, setUser] = useState(null);
  const [error, setError] = useState(null);
  const exchanged = useRef(false);

  // Shakha redirects back to /login?code=... (or ?error=...). Swap the
  // one-time code for a session token, then clean up the URL.
  useEffect(() => {
    if (window.location.pathname !== "/login" || exchanged.current) return;
    exchanged.current = true;

    const params = new URLSearchParams(window.location.search);
    window.history.replaceState({}, "", "/");

    if (params.get("error")) return setError(params.get("error"));
    if (!params.get("code")) return;

    fetch(`${AUTH}/session/exchange`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code: params.get("code") }),
    })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error("Code exchange failed"))))
      .then(({ token }) => {
        localStorage.setItem("token", token);
        setToken(token);
      })
      .catch((e) => setError(e.message));
  }, []);

  useEffect(() => {
    if (!token) return setUser(null);

    fetch(`${API}/me`, { headers: { Authorization: `Bearer ${token}` } })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error("Session expired"))))
      .then(setUser)
      .catch(() => {
        localStorage.removeItem("token");
        setToken(null);
      });
  }, [token]);

  async function signOut() {
    await fetch(`${AUTH}/sign_out`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
    });
    localStorage.removeItem("token");
    setToken(null);
  }

  return (
    <main style={{ fontFamily: "system-ui, sans-serif", maxWidth: 480, margin: "4rem auto", padding: "0 1rem" }}>
      <h1>Shakha example</h1>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
      {user ? (
        <>
          <p>
            Signed in as <strong>{user.name}</strong> ({user.email}) via {user.provider}.
          </p>
          <pre>{JSON.stringify(user, null, 2)}</pre>
          <button onClick={signOut}>Sign out</button>
        </>
      ) : (
        <button onClick={() => signIn("google")}>Sign in with Google</button>
      )}
    </main>
  );
}
