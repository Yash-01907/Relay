import express from "express";
import {prismaClient} from "./lib/prisma.js";

import { notFound } from "./middlewares/notFound.js";
import { errorHandler } from "./middlewares/errorHandler.js";

const app = express();

app.use(express.json());

app.get('/health',(req,res)=>{
    res.status(200).json({
        status:"Healthy",
        service:"Relay"
    })
})

app.get('/health/db', async (req,res)=>{
    try{
        await prismaClient.$queryRaw`SELECT 1`;
        res.status(200).json({
            status:"Healthy",
            service:"Relay",
            database:"Healthy"
        })
    } catch(err){
        res.status(503).json({
            status:"Unhealthy",
            service:"Relay",
            database:"Unhealthy"
        })
    }
})

app.use(notFound)
app.use(errorHandler)

export default app;