use ockam::{
    async_worker, Context, InnerVault, RemoteForwarder, Result, Routed, SecureChannel,
    SoftwareVault, Worker,
};
use ockam_transport_tcp::TcpTransport;

struct EchoService;

#[async_worker]
impl Worker for EchoService {
    type Message = String;
    type Context = Context;

    async fn handle_message(&mut self, ctx: &mut Context, msg: Routed<String>) -> Result<()> {
        println!("echo_service: {}", msg);
        ctx.send(msg.return_route(), msg.body()).await
    }
}

#[ockam::node]
async fn main(mut ctx: Context) -> Result<()> {
    let hub = "Paste the address of the node you created on Ockam Hub here.";

    let tcp = TcpTransport::create(&ctx).await?;

    tcp.connect(hub).await?;

    let vault_address = InnerVault::create(&ctx, SoftwareVault::default()).await?;

    SecureChannel::create_listener(&ctx, "secure_channel", &vault_address).await?;

    ctx.start_worker("echo_service", EchoService).await?;

    let mailbox = RemoteForwarder::create(&mut ctx, hub, "secure_channel").await?;

    println!(
        "echo_service secure channel address: {}",
        mailbox.remote_address()
    );
    Ok(())
}
