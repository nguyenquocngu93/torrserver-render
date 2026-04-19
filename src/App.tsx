import { useState, useEffect } from 'react'
import { supabase } from './lib/supabase'
import './App.css'

export default function App() {
  const [status, setStatus] = useState<string>('Loading...')

  useEffect(() => {
    const checkConnection = async () => {
      try {
        const { data, error } = await supabase.from('_supabase_migrations').select('id').limit(1)
        if (error) throw error
        setStatus('Connected to Supabase')
      } catch (err) {
        setStatus(`Connection error: ${err instanceof Error ? err.message : 'Unknown'}`)
      }
    }
    checkConnection()
  }, [])

  return (
    <div className="container">
      <h1>TorrServer Web</h1>
      <p className="status">{status}</p>
      <p className="info">Your Supabase database is ready to use.</p>
    </div>
  )
}
