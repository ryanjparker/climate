library(fda)
library(fields)
library(maps)
library(multicore)
library(rstan); set_cppo("fast")
library(MCMCpack)
library(mvtnorm)
library(splines)
library(coda)

source("R/plot_2d.R")
source("R/load_data2.R")
source("R/smooth_corr.R")
source("R/spline_cov.R")

cdata <- SumTemp
tlon  <- lon
tlat  <- lat
n1    <- nrow(cdata)
n2    <- ncol(cdata)

# plot this data
if (FALSE) {pdf("pdf/2d/data.pdf")
	par(bty="l")
	par(mfrow=c(2,2))
	image.plot(tlon,tlat,cdata[,,9],xlab="",ylab="",axes=F,main="Data");   map("world",add=T)
	image.plot(tlon,tlat,cdata[,,1],xlab="",ylab="",axes=F,main="BC");    map("world",add=T)
	image.plot(tlon,tlat,cdata[,,2],xlab="",ylab="",axes=F,main="RCM(2)"); map("world",add=T)
	image.plot(tlon,tlat,cdata[,,6],xlab="",ylab="",axes=F,main="RCM(6)"); map("world",add=T)
graphics.off()}

# plot Zs
if (FALSE) {pdf("pdf/2d/data_trans.pdf")
	par(bty="l")
	par(mfrow=c(2,2))
  image.plot(tlon,tlat,Z[,,9],xlab="",ylab="",axes=F,main="Data")
  image.plot(tlon,tlat,Z[,,1],xlab="",ylab="",axes=F,main="BC")
  image.plot(tlon,tlat,Z[,,2],xlab="",ylab="",axes=F,main="RCM(2)")
  image.plot(tlon,tlat,Z[,,6],xlab="",ylab="",axes=F,main="RCM(6)")
graphics.off()}

"get_weights_linear" <- function(d, L, knots) {
	if (length(knots) != L) {
		stop("get_weights_linear(): Number of knots unequal to L")
	}
	# construct weights from linear functions between knots
	if (L > 1) {
		weights <- matrix(0, nrow=length(d), ncol=L)
		for (l in 1:L) {
			if (l == 1) {
				weights[,l] <- as.integer(d >= knots[l]&d <= knots[l+1])*(knots[l+1]-d)/(knots[l+1]-knots[l])
			} else if (l == L) {
				weights[,l] <- as.integer(d >= knots[l-1]&d <= knots[l])*(1-(knots[l]-d)/(knots[l]-knots[l-1]))
			} else {
				weights[,l] <- as.integer(d >= knots[l-1]&d < knots[l])*(1-(knots[l]-d)/(knots[l]-knots[l-1])) +
				               as.integer(d >= knots[l]&d < knots[l+1])*(knots[l+1]-d)/(knots[l+1]-knots[l])
			}
		}
	}

	weights
}

if (TRUE) {
	# let's subset the data...
	z <- z[,c(1,5,9)]

	#keep <- T <= 40
	#keep <- c(1, 1+sort( sample.int(nrow(z)-1, size=round(nrow(z)/8)) ))
	#keep <- c(1, round(seq(2, nrow(z), len=round(nrow(z)/8))) )
	#z <- z[keep,]; d <- d[keep]; f <- f[keep]; T <- T[keep]
}

zstar <- sqrt(d) * z

#n  <- n1*n2
n  <- nrow(z)
k  <- ncol(z)
Nt <- max(T)

if (TRUE) {
	# compile once...
	weights <- get_weights(f, 1)$w; max_w <- rep(1, length(f)); i_max_w <- max_w; uf <- quantile(f, seq(0,1,length=10)); ufw <- get_weights(uf, 1)$w
	dat <- list(
		n=n, k=k, Zstar=zstar, L=1,
		weights=weights, i_max_w=i_max_w,
		nz_max=1, Nnz=rep(1, n), Mnz=matrix(1, nrow=n, ncol=1), Wnz=matrix(1, nrow=n, ncol=1),
		Nuf=length(uf), ufw=ufw,
		krho=round(k*(k-1)/2)
	)
	fit2d <- stan(file = 'stan/model_2d_uc_hier.stan', data = dat, iter = 10, chains = 1, init="0") #,pars="Omega");
	save(fit2d, file="fit2d.RData");
	done
} else {
	load("fit2d.RData")
}

"do_fit" <- function(ss=0.01, it=1, starts) {

	if (missing(starts))
		has_starts <- FALSE
	else
		has_starts <- TRUE

Ls <- THE_L
fits <- lapply(Ls, function(L) {
	# what kind of knot scheme to use?
	use_cknots <- FALSE
	use_bs     <- TRUE
	use_lin    <- FALSE

	if (use_lin) {
		#knots  <- c(min(f), 0.05, 0.10, seq(0.2, max(f), len=L-3))
		knots  <- seq(min(f), max(f), len=L)

		weights <- get_weights_linear(f, L, knots)
		#uf      <- seq(min(f),max(f),length=200)
		uf      <- unique(as.vector(unlist( sapply(1:(length(knots)-1), function(i) { seq(knots[i],knots[i+1],len=10) }) )))
		ufw     <- get_weights_linear(uf, L, knots)
print(head(weights))
print(head(ufw))
print(head(uf,20))
print(length(uf))
print(summary(rowSums(weights)))
print(summary(rowSums(ufw)))
	} else if (use_bs) {
		#bsknots  <- seq(min(f),max(f),len=L-3)[-c(1,L-3)]
		#weights <- bs(d, knots=bsknots, intercept=TRUE)
		if (L < 4) { stop("B-splines require L > 3\n") }
		#cknots  <- c(0.1, seq(0.2, max(d)-0.5, len=L-5))
		cknots  <- seq(min(f), max(f), len=L-2)[-c(1,L-2)]

		#cknots  <- c(0.1, seq(0.2, max(d), len=L-4)[-c(L-4)])
		#weights <- bs(d, df=L, intercept=TRUE)
		#weights <- bs(f, knots=cknots, intercept=TRUE, Boundary.knots=c(min(f),max(f)))
		#weights <- bs(f, knots=cknots, intercept=TRUE, Boundary.knots=c(min(f),max(f)))

		uf      <- quantile(f, seq(0,1,length=100))
		if (FALSE) { # specify DF
			weights <- bs(f, df=L, intercept=TRUE, Boundary.knots=c(min(f),max(f)))
			knots   <- f[apply(weights, 2, which.max)]
			ufw     <- predict(weights, uf)
		} else if (FALSE) { # specify own internal knots
			#weights <- bs(f, knots=cknots, intercept=TRUE, Boundary.knots=c(min(f),max(f)))
			bsf <- bs(f, knots=cknots, intercept=FALSE, Boundary.knots=c(min(f),max(f)))
			weights <- cbind(1, bsf)
			knots   <- cknots
			ufw     <- cbind(1, predict(bsf, uf))
		} else { # use FDA package w/ cubic b-splines (norder=4)
			Bspline.basis <- create.bspline.basis(c(min(f),max(f)),norder=4,nbasis=L)
			knots   <- knots(Bspline.basis)
			weights <- getbasismatrix(f, Bspline.basis, nderiv=0)
			ufw     <- getbasismatrix(uf, Bspline.basis, nderiv=0)
		}
		#ufw     <- bs(uf, knots=cknots, intercept=TRUE, Boundary.knots=c(min(f),max(f)))
		#ufw     <- bs(uf, df=L, intercept=TRUE, Boundary.knots=c(min(f),max(f)))

		# capture which are non-zero
		nz <- apply(weights, 1, function(x){ which(x!=0) })

		# get number of non-zeros
		Nnz <- sapply(1:length(nz), function(i){ length(nz[[i]]) })

		# get non-zero indices
		Mnz <- matrix(0, nrow=length(nz), ncol=max(Nnz))
		sapply(1:length(nz), function(i){ Mnz[i,1:Nnz[i]] <<- nz[[i]] })

		# get non-zero weights
		Wnz <- matrix(0, nrow=length(nz), ncol=max(Nnz))
		sapply(1:length(nz), function(i){ Wnz[i,1:Nnz[i]] <<- weights[i,nz[[i]]] })

if (TRUE) {
print(head(Mnz))
print(tail(Mnz))
print(head(Wnz))
print(tail(Wnz))

print(class(Nnz))
print(summary(Nnz))
print(head(Nnz))
print(knots)
}
	} else if (use_cknots) {
		#cknots  <- c(min(d), 1, 2, 3, seq(4, max(d), len=L-4))  # put more dots near where function moves
		#cknots  <- c(seq(min(d), 4, len=L-4), 5, 6, 7, max(d))  # put more dots near where function moves
		cknots  <- c( seq(0, 1, len=L-10), 1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 7, max(f))  # put more dots near where function moves
		weights <- get_weights(f, L, cknots)$w
		knots   <- get_weights(f, L, cknots)$knots
		uf      <- quantile(f, seq(0,1,length=100))
		ufw     <- get_weights(uf, L)$w
	} else {
		weights <- get_weights(f, L)$w
		knots   <- get_weights(f, L)$knots
		uf      <- quantile(f, seq(0,1,length=100))
		ufw     <- get_weights(uf, L)$w
	}
	max_w   <- apply(weights, 1, max)
	i_max_w <- apply(weights, 1, which.max)

	krho <- round(k*(k-1)/2)
	dat = list(n=n, k=k, Zstar=zstar,
		L=L, weights=weights, i_max_w=i_max_w,
		nz_max=max(Nnz), Nnz=Nnz, Mnz=Mnz, Wnz=Wnz,
		Nuf=length(uf), ufw=ufw,
		krho=krho
	)

	# function to get initial values
	fn.inits <- function() {
		fq <- quantile(f, probs=(0:L)/L)
		omega <- array(NA, dim=c(L,k))
		corrOmega <- array(NA, dim=c(L,k,k))
		for (l in 1:L) {
			#corrOmega[l,,] <- rWishart(1, k+10, diag(k))[,,1]
			#omega[l,] <- 2*rep(1, k)/l
			omega[l,] <- apply(zstar[f > fq[l]&d <= fq[l+1],], 2, sd)
			corrOmega[l,,] <- diag(k)
			#corrOmega[l,,] <- cov2cor(corrOmega[l,,])
		}

		list("omega"=omega, "corrOmega"=corrOmega, "alpha"=array(rnorm(n*L*k), dim=c(n,L,k)))
	}

	# function to generate random initial values
	fn.rinits <- function() {
		omega <- array(NA, dim=c(L,k))
		corrOmega <- array(NA, dim=c(L,k,k))
		for (l in 1:L) {
			omega[l,] <- runif(k, 0.5, 2)
			corrOmega[l,,] <- rWishart(1, k+10, diag(k))[,,1]
			corrOmega[l,,] <- cov2cor(corrOmega[l,,])
			corrOmega[l,,] <- ifelse(corrOmega[l,,] < 0, 0, corrOmega[l,,])
		}

		r <- list("omega"=omega, "corrOmega"=corrOmega, "alpha"=array(rnorm(n*L*k), dim=c(n,L,k)))

		r
	}

	# function to get initial values with fixed correlation
	fn.finits <- function() {
		omega <- array(NA, dim=c(L,k))
		corrOmega <- array(NA, dim=c(L,k,k))
		ests <- ls_estimates(sc, L)

		for (l in 1:L) {
			omega[l,] <- runif(k, 0.5, 2)

			corrOmega[l,,] <- ests[[l]]
		}

		r <- list("omega"=omega, "corrOmega"=corrOmega) #, "alpha"=array(rnorm(n*L*k), dim=c(n,L,k)))
print(round(r$corrOmega[1,,],3))
print(round(r$corrOmega[L,,],3))

		r
	}

	fn.uinits <- function() {
		kcor <- k*(k-1)/2
		r <- list(
			s=array(runif(k*L,-1,1), dim=c(k,L)),
			r=array(runif(kcor*L,0,2), dim=c(kcor,L))
		)
#print(r$r)

		r
	}

STAN <- FALSE

if (STAN) {
	# run in parallel
	Niter <- 100
	if (L == 5)  Niter <- 100
	if (L == 10) Niter <- 100
	if (L == 15) Niter <- 100
	if (L == 20) Niter <- 100
	Nchains <- 3
	Ncores  <- 3

	if (WHICH_CDAT == "ST" | WHICH_CDAT == "WT") delta  <- 0.8; max_td <- 8
	if (WHICH_CDAT == "SP" | WHICH_CDAT == "WP") delta  <- 0.8; max_td <- 8

	sflist <- mclapply(1:Nchains, mc.cores=Ncores,
		function(i) {
			tf <- stan(fit=fit2d, data=dat, iter=Niter, init="0", #init=fn.uinits,
			           algorithm="HMC", control=list(adapt_engaged=FALSE, stepsize=ss, int_time=it, metric="unit_e"),
			           #control=list(adapt_delta=delta, max_treedepth=max_td),
			           #control=list(metric="unit_e", max_treedepth=max_td),
			           #control=list(adapt_delta=delta, max_treedepth=max_td),
			           chains = 1, seed=311311, chain_id=i, refresh=5, verbose=TRUE#,
			           #pars=c("Dbar","corrSigma_f","Omega")
			           #pars=c("Dbar","Omega")
			           #pars=c("s","r")
			)

			#save(tf, file=paste0("tmp/fit",i,".RData"))

			tf
		}
	)

	if (length(sflist) > 1) {
		cat("Merging fits...\n")
		#sflist <- vector("list", Nchains)
		#for (i in 1:Nchains) {
		#	load(paste0("tmp/fit",i,".RData"))
		#	sflist[[i]] <- tf
		#}
		fit <- sflist2stanfit(sflist)
	} else {
		fit <- sflist[[1]]
	}
	rm("sflist")

	cat("Computing fit summary..\n")
	fitsum <- summary(fit)$summary

	# compute DIC
	cat("Computing DIC...\n")

	dbar <- fitsum[grep("Dbar", rownames(fitsum)),1]

if (FALSE) {
	# random effect version
	svars <- list(
		"Omega"=aperm( array(fitsum[grep("^Omega",rownames(fitsum)),1],dim=c(k,k,L)), c(3,2,1) )
	)

	#Omegas <- extract(fit)$Omega

	cat("Dhat...\n")
	dhat <- sum( sapply(2:n, function(i) {
		i_Omega <- matrix(0, nrow=k, ncol=k)
		for (l in 1:L) {
			i_Omega <- i_Omega + weights[i,l] * svars$Omega[l,,]
		}
		-2 * dmvnorm(dat$Zstar[i,], rep(0, k), i_Omega, log=TRUE)
	}) )

	pD  <- dbar - dhat
	DIC <- dbar + pD
} else if (TRUE) {
	# cholesky version
	svars <- list(
		#"s"=aperm( array(fitsum[grep("^s",rownames(fitsum)),1],dim=c(L,k)), c(2,1) )
		"s"=aperm( array(fitsum[grep("^s",rownames(fitsum)),1],dim=c(L,k)), c(2,1) ),
		"r"=aperm( array(fitsum[grep("^r",rownames(fitsum)),1],dim=c(L,krho)), c(2,1) )
	)

	cat("Dhat...\n")
	dhat <- sum( sapply(2:n, function(i) {
		i_L <- matrix(0, nrow=k, ncol=k)

		for (k1 in 1:k) i_L[k1,k1] <- exp( crossprod(weights[i,], svars$s[k1,]) )

		c <- 1
		for (k1 in 1:(k-1)) {
			for (k2 in (k1+1):k) {
				i_L[k2,k1] <- crossprod(weights[i,], svars$r[c,])
				c <- c+1
			}
		}

		#ll1 <- -2 * ( -0.5*k * log(2*pi) -0.5 * log( det(i_L %*% t(i_L)) ) -0.5*t(dat$Zstar[i,]) %*% solve( i_L %*% t(i_L) ) %*% dat$Zstar[i,] )
		ll2 <- k*log(2*pi) +2*sum(log(diag(i_L))) +t(dat$Zstar[i,]) %*% chol2inv( t(i_L) ) %*% dat$Zstar[i,]
#if (i <= 5) print(c(ll1,ll2))

#if (i < 5) print(ll2)

		#ll1
		ll2
	}) )

	pD  <- dbar - dhat
	DIC <- dbar + pD

} else {
	pD  <- 0
	DIC <- 0
}

	sp<-get_sampler_params(fit)
	ini <- get_inits(fit)

	print(object.size(fit),units="Mb")
	#rm("fit")

	# save fit
	cat("Saving fitsum...\n")
	if (use_lin) {
		fname <- paste0("linL",L,"_",WHICH_CDAT,".RData")
	} else if (use_bs) {
		fname <- paste0("bsL",L,"_",WHICH_CDAT,".RData")
	} else if (use_cknots) {
		fname <- paste0("cL",L,"_",WHICH_CDAT,".RData")
	} else {
		fname <- paste0("L",L,"_",WHICH_CDAT,".RData")
	}
	save(L, fitsum, sp, ini, uf, ufw, knots, DIC, pD, file=paste0("fitsums/fitsum_",fname))
	#save(sp, file=paste0("fitsums/fit_",fname))

	list(L=L, ini=ini, sp=sp, fitsum=fitsum, DIC=DIC, pD=pD)
} else { # end do stan

	Niter <- 50
	Nburn <- 10
	Nchains <- 3
	Ncores  <- 3
	Nparam <- L*(dat$k + dat$k*(dat$k-1)/2)
	prior.sd <- 1

	if (!has_starts) {
		# get initial values with BFGS
		init <- rep(0, Nparam)
		t1 <- proc.time()
		bfgs <- optim(par=init,
			fn=function(x) {
				lk <- spline_cov_lk(prior=prior.sd, n=dat$n, k=dat$k, y=z, L=dat$L, Nnz=dat$Nnz, Mnz=dat$Mnz-1, Wnz=dat$Wnz, eval=x)$lk
				-lk
			},
			gr=function(x) {
				gr <- spline_cov_gr(prior=prior.sd, n=dat$n, k=dat$k, y=z, L=dat$L, Nnz=dat$Nnz, Mnz=dat$Mnz-1, Wnz=dat$Wnz, eval=x)
				-gr
			},
		method="BFGS", control=list(maxit=5000))
		print(proc.time()-t1)
		init <- bfgs$par
	} else {
		init <- starts
		bfgs <- NA
	}

	samples <- matrix(0, nrow=Niter, ncol=Nparam)

	t1 <- proc.time()

	fits <- mclapply(1:Nchains, mc.cores=Ncores,
		function(i) {
		set.seed(311*i);
		fit <- spline_cov(prior=prior.sd,
		  n=dat$n, k=dat$k, y=z, L=dat$L, Nnz=dat$Nnz, Mnz=dat$Mnz-1, Wnz=dat$Wnz,
		  step_e=ss, step_L=it, inits=init, Niter=Niter, samples=samples, verbose=TRUE)
	})

	# compute DIC

	# get samples, discarding burn
	sub <- -(1:Nburn)
	res <- vector("list", Nchains)
	dev <- vector("list", Nchains)
	for (i in 1:Nchains) {
		res[[i]] <- matrix(fits[[i]]$samples, nrow=Niter)[sub,]
		dev[[i]] <- matrix(fits[[i]]$deviance, nrow=Niter)[sub,]
	}

  # posterior mean
  pmean <- colMeans( do.call(rbind, res) )
  dmean <- mean( unlist(dev) )

  Dbar  <- dmean
  Dtbar <- -2*spline_cov_lk(prior=prior.sd, n=dat$n, k=dat$k, y=z, L=dat$L, Nnz=dat$Nnz, Mnz=dat$Mnz-1, Wnz=dat$Wnz, eval=pmean)$llik
  pD    <- Dbar - Dtbar
	DIC   <- Dbar + pD


	# save fit
	if (use_lin) {
		fname <- paste0("linL",L,"_",WHICH_CDAT,".RData")
	} else if (use_bs) {
		fname <- paste0("bsL",L,"_",WHICH_CDAT,".RData")
	} else if (use_cknots) {
		fname <- paste0("cL",L,"_",WHICH_CDAT,".RData")
	} else {
		fname <- paste0("L",L,"_",WHICH_CDAT,".RData")
	}
	save(L, fits, res, bfgs, DIC, pD, uf, ufw, knots, file=paste0("fitsums/fitsum_",fname))

	list(L=L, fits=fits, res=res, bfgs=bfgs, DIC=DIC, pD=pD)
} # don't do stan

})

}

#fit <- do_fit(0.05, 25) #, good_starts)
#fit <- do_fit(0.025, 5) #, good_starts)
#fit <- do_fit(0.025, 2^9) #, good_starts)

#fit1 <- do_fit(0.025, 5) #, good_starts)
#fit2 <- do_fit(0.025, 10) #, good_starts)
#fit3 <- do_fit(0.025, 15) #, good_starts)
fit4 <- do_fit(0.025, 20) #, good_starts)

#eps <- .0001; f1 <- do_fit(eps, 10*eps)
#eps <- .00001; f2 <- do_fit(eps, 10*eps)
#eps <- .000001; f3 <- do_fit(eps, 10*eps)
#eps <- .0000001; f4 <- do_fit(eps, 10*eps)
#eps <- .0001; f1 <- do_fit(eps, 10*eps)
#eps <- .0001; f2 <- do_fit(eps, 50*eps)
#eps <- .0001; f3 <- do_fit(eps, 100*eps)
#eps <- .0001; f4 <- do_fit(eps, 150*eps)
#eps <- .0001; f5 <- do_fit(eps, 200*eps)
#eps <- .0001; f6 <- do_fit(eps, 250*eps)
#eps <- .0001; f7 <- do_fit(eps, 512*eps)
#eps <- .0001; f8 <- do_fit(eps, 1024*eps)
#eps <- .0001; fs <- do_fit(eps, 1024*eps)

#round(sapply(1:nrow(ufw),function(i){ 2*invlogit( sum(v3*ufw[i,]) )-1 }),2)

