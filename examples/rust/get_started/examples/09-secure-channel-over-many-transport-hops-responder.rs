use ockam::{Context, Result, SecureChannel, Vault, TcpTransport};
use ockam_get_started::Echoer;

#[ockam::node]
async fn main(mut ctx: Context) -> Result<()> {
    let tcp = TcpTransport::create(&ctx).await?;
    tcp.listen("127.0.0.1:6000").await?;

    let vault = Vault::create(&ctx).await?;

    SecureChannel::create_listener(&mut ctx, "secure_channel_listener", &vault).await?;

    // Create an echoer worker
    ctx.start_worker("echoer", Echoer).await?;

    // This node never shuts down.
    Ok(())
}
