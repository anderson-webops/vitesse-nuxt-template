import cors from 'cors'
import express from 'express'
import helmet from 'helmet'

const startedAt = Date.now()
let pageview = 0

export function createApp() {
  const app = express()

  app.disable('x-powered-by')
  app.use(helmet({ contentSecurityPolicy: false }))
  app.use(cors({ origin: true, credentials: true }))
  app.use(express.json())

  app.get('/api/health', (_request, response) => {
    response.json({
      ok: true,
      startedAt,
    })
  })

  app.get('/api/pageview', (_request, response) => {
    response.json({
      pageview: pageview++,
      startAt: startedAt,
    })
  })

  return app
}
